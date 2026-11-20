#include "engine-adapter.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#ifdef MEDIAKIT_HAVE_MPV
#include <epoxy/gl.h>
#include <mpv/client.h>
#include <mpv/render.h>
#include <mpv/render_gl.h>
#endif

typedef enum {
    SIGNAL_ENDED,
    SIGNAL_FAILED,
    SIGNAL_PAUSE_CHANGED,
    SIGNAL_POSITION_CHANGED,
    SIGNAL_DURATION_CHANGED,
    SIGNAL_METADATA_CHANGED,
    SIGNAL_BUFFERING_CHANGED,
    SIGNAL_SEEKING_CHANGED,
    SIGNAL_CHAPTER_CHANGED,
    SIGNAL_SUBTITLE_VISIBILITY_CHANGED,
    SIGNAL_OPERATION_FAILED,
    SIGNAL_VIDEO_DECODER_CHANGED,
    SIGNAL_COLOR_METADATA_CHANGED,
    SIGNAL_AUDIO_METADATA_CHANGED,
    SIGNAL_AUDIO_DEVICES_CHANGED,
    SIGNAL_COUNT
} EngineSignal;

static guint engine_signals[SIGNAL_COUNT];
static guint renderer_update_signal;

struct _MediaKitEngine {
    GObject parent_instance;
    GMainContext *context;
    GTask *open_task;
    gulong cancel_id;
    gint64 last_position_us;
    gboolean paused_for_cache;
    gint buffering_percent;
    gint pending_event_dispatch;
    struct _MediaKitRenderer *active_renderer;
    gboolean closing;
    gboolean disc_source;
    gboolean disc_menu_supported;
    gboolean pq_output_requested;
#ifdef MEDIAKIT_HAVE_MPV
    mpv_handle *player;
#endif
};

struct _MediaKitRenderer {
    GObject parent_instance;
    MediaKitEngine *engine;
    GMainContext *context;
    gboolean released;
    gint pending_renderer_dispatch;
    gint red_bits;
    gint green_bits;
    gint blue_bits;
    gint render_depth_bits;
    gboolean icc_profile_active;
    gboolean frame_submitted;
    gboolean experimental_gpu_next;
    gboolean framebuffer_information_valid;
    gint last_framebuffer;
#ifdef MEDIAKIT_HAVE_MPV
    mpv_render_context *render_context;
#endif
};

G_DEFINE_TYPE(MediaKitEngine, mediakit_engine, G_TYPE_OBJECT)
G_DEFINE_TYPE(MediaKitRenderer, mediakit_renderer, G_TYPE_OBJECT)

#ifdef MEDIAKIT_HAVE_MPV
/** Converts a libmpv status into a stable GLib error contract. */
static void
set_mpv_error(GError **error, int status, const gchar *operation)
{
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                "%s: %s", operation, mpv_error_string(status));
}
#endif

/** Returns the build-time playback capability without claiming successful device output. */
gboolean
mediakit_engine_is_available(void)
{
#ifdef MEDIAKIT_HAVE_MPV
    return TRUE;
#else
    return FALSE;
#endif
}

/** Explains the explicitly disabled libmpv configuration. */
const gchar *
mediakit_engine_unavailable_reason(void)
{
    return "This build does not contain the libmpv playback backend";
}

/** Completes the pending task once, disconnecting its cancellation callback. */
static void
complete_open(MediaKitEngine *self, GError *error)
{
    GTask *task;
    GCancellable *cancellable;

    if (self->open_task == NULL) {
        g_clear_error(&error);
        return;
    }

    task = g_steal_pointer(&self->open_task);
    cancellable = g_task_get_cancellable(task);
    if (cancellable != NULL && self->cancel_id != 0) {
        g_cancellable_disconnect(cancellable, self->cancel_id);
        self->cancel_id = 0;
    }

    if (!g_task_return_error_if_cancelled(task)) {
        if (error != NULL) {
            g_task_return_error(task, error);
            error = NULL;
        } else {
            g_task_return_boolean(task, TRUE);
        }
    }

    g_clear_error(&error);
    g_object_unref(task);
}

/** Completes cancellation on the engine's owning main context. */
static gboolean
complete_cancellation(gpointer data)
{
    MediaKitEngine *self = MEDIAKIT_ENGINE(data);

    if (self->open_task != NULL) {
        complete_open(self, g_error_new_literal(G_IO_ERROR, G_IO_ERROR_CANCELLED,
                                                "Media loading was canceled"));
#ifdef MEDIAKIT_HAVE_MPV
        if (self->player != NULL) {
            const char *command[] = { "stop", NULL };
            mpv_command_async(self->player, 0, command);
        }
#endif
    }

    return G_SOURCE_REMOVE;
}

/** Dispatches a thread-safe cancellable signal to the main-context owner. */
static void
on_load_cancelled(GCancellable *cancellable, gpointer data)
{
    MediaKitEngine *self = MEDIAKIT_ENGINE(data);
    GSource *source = g_idle_source_new();
    (void)cancellable;
    g_source_set_callback(source, complete_cancellation, g_object_ref(self), g_object_unref);
    g_source_attach(source, self->context);
    g_source_unref(source);
}

#ifdef MEDIAKIT_HAVE_MPV
/** Drains already-queued libmpv events without blocking GTK's main context. */
static gboolean
process_events(gpointer data)
{
    MediaKitEngine *self = MEDIAKIT_ENGINE(data);

    g_atomic_int_set(&self->pending_event_dispatch, 0);
    if (self->player == NULL || self->closing) {
        return G_SOURCE_REMOVE;
    }

    for (;;) {
        mpv_event *event = mpv_wait_event(self->player, 0);
        if (event->event_id == MPV_EVENT_NONE) {
            break;
        }

        switch (event->event_id) {
        case MPV_EVENT_FILE_LOADED:
            g_signal_emit(self, engine_signals[SIGNAL_METADATA_CHANGED], 0);
            g_signal_emit(self, engine_signals[SIGNAL_COLOR_METADATA_CHANGED], 0);
            g_signal_emit(self, engine_signals[SIGNAL_AUDIO_METADATA_CHANGED], 0);
            g_signal_emit(self, engine_signals[SIGNAL_AUDIO_DEVICES_CHANGED], 0);
            complete_open(self, NULL);
            break;
        case MPV_EVENT_COMMAND_REPLY:
            if (event->error < 0) {
                if (self->open_task != NULL && event->reply_userdata == 1) {
                    complete_open(self, g_error_new(G_IO_ERROR, G_IO_ERROR_FAILED,
                                                    "Unable to load media: %s",
                                                    mpv_error_string(event->error)));
                } else if (event->reply_userdata == 31 ||
                           event->reply_userdata == 33) {
                    g_signal_emit(self, engine_signals[SIGNAL_OPERATION_FAILED], 0,
                                  mpv_error_string(event->error));
                }
            }
            break;
        case MPV_EVENT_SET_PROPERTY_REPLY:
            if (event->error < 0 && (event->reply_userdata == 32 ||
                                     event->reply_userdata == 34 ||
                                     event->reply_userdata == 35)) {
                g_signal_emit(self, engine_signals[SIGNAL_OPERATION_FAILED], 0,
                              mpv_error_string(event->error));
            }
            break;
        case MPV_EVENT_END_FILE: {
            mpv_event_end_file *end = event->data;
            if (end != NULL && end->reason == MPV_END_FILE_REASON_ERROR) {
                const gchar *reason = mpv_error_string(end->error);
                if (self->open_task != NULL) {
                    complete_open(self, g_error_new(G_IO_ERROR, G_IO_ERROR_FAILED,
                                                    "Media open failed: %s", reason));
                } else {
                    g_signal_emit(self, engine_signals[SIGNAL_FAILED], 0, reason);
                }
            } else if (end != NULL && end->reason == MPV_END_FILE_REASON_EOF) {
                g_signal_emit(self, engine_signals[SIGNAL_ENDED], 0);
            }
            break;
        }
        case MPV_EVENT_PROPERTY_CHANGE: {
            mpv_event_property *property = event->data;
            if (property == NULL) {
                break;
            }
            if (property->format == MPV_FORMAT_NONE &&
                (g_strcmp0(property->name, "audio-params") == 0 ||
                 g_strcmp0(property->name, "audio-out-params") == 0 ||
                 g_strcmp0(property->name, "audio-device") == 0 ||
                 g_strcmp0(property->name, "current-ao") == 0 ||
                 g_strcmp0(property->name, "current-tracks/audio/codec") == 0)) {
                g_signal_emit(self, engine_signals[SIGNAL_AUDIO_METADATA_CHANGED], 0);
                break;
            }
            if (property->format == MPV_FORMAT_NONE &&
                g_strcmp0(property->name, "audio-device-list") == 0) {
                g_signal_emit(self, engine_signals[SIGNAL_AUDIO_DEVICES_CHANGED], 0);
                break;
            }
            if (property->format == MPV_FORMAT_NONE &&
                g_strcmp0(property->name, "video-params") == 0) {
                g_signal_emit(self, engine_signals[SIGNAL_COLOR_METADATA_CHANGED], 0);
                break;
            }
            if (property->format == MPV_FORMAT_NONE &&
                (g_strcmp0(property->name, "track-list") == 0 ||
                 g_strcmp0(property->name, "chapter-list") == 0 ||
                 g_strcmp0(property->name, "edition-list") == 0 ||
                 g_strcmp0(property->name, "edition") == 0 ||
                 g_strcmp0(property->name, "disc-title-list") == 0 ||
                 g_strcmp0(property->name, "disc-title") == 0 ||
                 g_strcmp0(property->name, "disc-menu-active") == 0)) {
                g_signal_emit(self, engine_signals[SIGNAL_METADATA_CHANGED], 0);
                break;
            }
            if (property->data == NULL) {
                break;
            }
            if (g_strcmp0(property->name, "pause") == 0 &&
                property->format == MPV_FORMAT_FLAG) {
                gboolean paused = *(int *)property->data != 0;
                g_signal_emit(self, engine_signals[SIGNAL_PAUSE_CHANGED], 0, paused);
            } else if (g_strcmp0(property->name, "time-pos") == 0 &&
                       property->format == MPV_FORMAT_DOUBLE) {
                double seconds = *(double *)property->data;
                if (!isfinite(seconds) || seconds < 0.0 ||
                    seconds > (double)G_MAXINT64 / 1000000.0) {
                    break;
                }
                gint64 position_us = (gint64)(seconds * 1000000.0);
                if (llabs(position_us - self->last_position_us) >= 100000) {
                    self->last_position_us = position_us;
                    g_signal_emit(self, engine_signals[SIGNAL_POSITION_CHANGED], 0,
                                  position_us);
                }
            } else if (g_strcmp0(property->name, "duration") == 0 &&
                       property->format == MPV_FORMAT_DOUBLE) {
                double seconds = *(double *)property->data;
                if (!isfinite(seconds) || seconds < 0.0 ||
                    seconds > (double)G_MAXINT64 / 1000000.0) {
                    break;
                }
                gint64 duration_us = (gint64)(seconds * 1000000.0);
                g_signal_emit(self, engine_signals[SIGNAL_DURATION_CHANGED], 0,
                              duration_us);
            } else if (g_strcmp0(property->name, "paused-for-cache") == 0 &&
                       property->format == MPV_FORMAT_FLAG) {
                self->paused_for_cache = *(int *)property->data != 0;
                g_signal_emit(self, engine_signals[SIGNAL_BUFFERING_CHANGED], 0,
                              self->paused_for_cache, self->buffering_percent);
            } else if (g_strcmp0(property->name, "cache-buffering-state") == 0 &&
                       property->format == MPV_FORMAT_INT64) {
                gint64 percent = *(int64_t *)property->data;
                self->buffering_percent = (gint)CLAMP(percent, 0, 100);
                g_signal_emit(self, engine_signals[SIGNAL_BUFFERING_CHANGED], 0,
                              self->paused_for_cache, self->buffering_percent);
            } else if (g_strcmp0(property->name, "seeking") == 0 &&
                       property->format == MPV_FORMAT_FLAG) {
                g_signal_emit(self, engine_signals[SIGNAL_SEEKING_CHANGED], 0,
                              *(int *)property->data != 0);
            } else if (g_strcmp0(property->name, "chapter") == 0 &&
                       property->format == MPV_FORMAT_INT64) {
                gint64 chapter = *(int64_t *)property->data;
                if (chapter >= -1 && chapter <= G_MAXINT) {
                    g_signal_emit(self, engine_signals[SIGNAL_CHAPTER_CHANGED], 0,
                                  (gint)chapter);
                }
            } else if (g_strcmp0(property->name, "sub-visibility") == 0 &&
                       property->format == MPV_FORMAT_FLAG) {
                g_signal_emit(self,
                              engine_signals[SIGNAL_SUBTITLE_VISIBILITY_CHANGED], 0,
                              *(int *)property->data != 0);
            } else if (g_strcmp0(property->name, "hwdec-current") == 0 &&
                       property->format == MPV_FORMAT_STRING) {
                const char *decoder = *(char **)property->data;
                g_signal_emit(self, engine_signals[SIGNAL_VIDEO_DECODER_CHANGED], 0,
                              decoder != NULL ? decoder : "");
            }
            break;
        }
        default:
            break;
        }
    }

    return G_SOURCE_REMOVE;
}

/** Schedules an event drain; mpv invokes this callback on arbitrary threads. */
static void
on_mpv_wakeup(void *data)
{
    MediaKitEngine *self = MEDIAKIT_ENGINE(data);
    GSource *source;
    if (!g_atomic_int_compare_and_exchange(&self->pending_event_dispatch, 0, 1)) {
        return;
    }
    source = g_idle_source_new();
    g_source_set_callback(source, process_events, g_object_ref(self), g_object_unref);
    g_source_attach(source, self->context);
    g_source_unref(source);
}

/** Schedules a renderer notification on its owning GTK main context. */
static gboolean
emit_renderer_update(gpointer data)
{
    MediaKitRenderer *self = MEDIAKIT_RENDERER(data);
    g_atomic_int_set(&self->pending_renderer_dispatch, 0);
    if (!self->released) {
        g_signal_emit(self, renderer_update_signal, 0);
    }
    return G_SOURCE_REMOVE;
}

/** Isolates the render-update callback from GTK and GObject thread affinity. */
static void
on_render_update(void *data)
{
    MediaKitRenderer *self = MEDIAKIT_RENDERER(data);
    GSource *source;
    if (!g_atomic_int_compare_and_exchange(&self->pending_renderer_dispatch, 0, 1)) {
        return;
    }
    source = g_idle_source_new();
    g_source_set_callback(source, emit_renderer_update, g_object_ref(self), g_object_unref);
    g_source_attach(source, self->context);
    g_source_unref(source);
}

/** Resolves GL functions using the current GTK-owned OpenGL context. */
static void *
resolve_gl(void *context, const char *name)
{
    (void)context;
    return epoxy_get_proc_address(name);
}
#endif

/** Initializes a private native object; libmpv initialization is deferred to construction. */
static void
mediakit_engine_init(MediaKitEngine *self)
{
    self->context = g_main_context_ref_thread_default();
    self->last_position_us = 0;
    self->buffering_percent = -1;
#ifdef MEDIAKIT_HAVE_MPV
    self->player = NULL;
#endif
}

/** Cancels pending work and releases the native player on the owning thread. */
static void
mediakit_engine_dispose(GObject *object)
{
    MediaKitEngine *self = MEDIAKIT_ENGINE(object);
    mediakit_engine_close(self);
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player != NULL) {
        mpv_set_wakeup_callback(self->player, NULL, NULL);
        mpv_terminate_destroy(self->player);
        self->player = NULL;
    }
#endif
    G_OBJECT_CLASS(mediakit_engine_parent_class)->dispose(object);
}

/** Releases the GLib context after the native player has been disposed. */
static void
mediakit_engine_finalize(GObject *object)
{
    MediaKitEngine *self = MEDIAKIT_ENGINE(object);
    g_clear_pointer(&self->context, g_main_context_unref);
    G_OBJECT_CLASS(mediakit_engine_parent_class)->finalize(object);
}

/** Declares the minimal event contract needed by the Vala playback backend. */
static void
mediakit_engine_class_init(MediaKitEngineClass *klass)
{
    GObjectClass *object_class = G_OBJECT_CLASS(klass);
    object_class->dispose = mediakit_engine_dispose;
    object_class->finalize = mediakit_engine_finalize;
    engine_signals[SIGNAL_ENDED] = g_signal_new("ended", G_TYPE_FROM_CLASS(klass),
        G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL, G_TYPE_NONE, 0);
    engine_signals[SIGNAL_FAILED] = g_signal_new("failed", G_TYPE_FROM_CLASS(klass),
        G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL, G_TYPE_NONE, 1, G_TYPE_STRING);
    engine_signals[SIGNAL_PAUSE_CHANGED] = g_signal_new("pause-changed",
        G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL,
        G_TYPE_NONE, 1, G_TYPE_BOOLEAN);
    engine_signals[SIGNAL_POSITION_CHANGED] = g_signal_new("position-changed",
        G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL,
        G_TYPE_NONE, 1, G_TYPE_INT64);
    engine_signals[SIGNAL_DURATION_CHANGED] = g_signal_new("duration-changed",
        G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL,
        G_TYPE_NONE, 1, G_TYPE_INT64);
    engine_signals[SIGNAL_METADATA_CHANGED] = g_signal_new("metadata-changed",
        G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL,
        G_TYPE_NONE, 0);
    engine_signals[SIGNAL_BUFFERING_CHANGED] = g_signal_new("buffering-changed",
        G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL,
        G_TYPE_NONE, 2, G_TYPE_BOOLEAN, G_TYPE_INT);
    engine_signals[SIGNAL_SEEKING_CHANGED] = g_signal_new("seeking-changed",
        G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL,
        G_TYPE_NONE, 1, G_TYPE_BOOLEAN);
    engine_signals[SIGNAL_CHAPTER_CHANGED] = g_signal_new("chapter-changed",
        G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL,
        G_TYPE_NONE, 1, G_TYPE_INT);
    engine_signals[SIGNAL_SUBTITLE_VISIBILITY_CHANGED] = g_signal_new(
        "subtitle-visibility-changed", G_TYPE_FROM_CLASS(klass),
        G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL, G_TYPE_NONE, 1, G_TYPE_BOOLEAN);
    engine_signals[SIGNAL_OPERATION_FAILED] = g_signal_new("operation-failed",
        G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL,
        G_TYPE_NONE, 1, G_TYPE_STRING);
    engine_signals[SIGNAL_VIDEO_DECODER_CHANGED] = g_signal_new(
        "video-decoder-changed", G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST,
        0, NULL, NULL, NULL, G_TYPE_NONE, 1, G_TYPE_STRING);
    engine_signals[SIGNAL_COLOR_METADATA_CHANGED] = g_signal_new(
        "color-metadata-changed", G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST,
        0, NULL, NULL, NULL, G_TYPE_NONE, 0);
    engine_signals[SIGNAL_AUDIO_METADATA_CHANGED] = g_signal_new(
        "audio-metadata-changed", G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST,
        0, NULL, NULL, NULL, G_TYPE_NONE, 0);
    engine_signals[SIGNAL_AUDIO_DEVICES_CHANGED] = g_signal_new(
        "audio-devices-changed", G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST,
        0, NULL, NULL, NULL, G_TYPE_NONE, 0);
}

/** Allocates a playback engine with an explicitly selected color-transfer target. */
MediaKitEngine *
mediakit_engine_new_with_video_target(const gchar *device_id, const gchar *codecs,
                                      const gchar *pcm_channels,
                                      const gchar *tone_mapping, gboolean deband,
                                      gboolean experimental_pq)
{
    MediaKitEngine *self = g_object_new(MEDIAKIT_TYPE_ENGINE, NULL);
    self->pq_output_requested = experimental_pq;
#ifdef MEDIAKIT_HAVE_MPV
    int status;
    self->player = mpv_create();
    if (self->player == NULL) {
        return self;
    }
#ifndef MEDIAKIT_EXPERIMENTAL_EMBEDDED_GPU_NEXT
    if (experimental_pq) {
        mpv_terminate_destroy(self->player);
        self->player = NULL;
        return self;
    }
#endif
    mpv_set_option_string(self->player, "vo", "libmpv");
    mpv_set_option_string(self->player, "hwdec", "auto-safe");
    mpv_set_option_string(self->player, "terminal", "no");
    mpv_set_option_string(self->player, "pause", "yes");
    mpv_set_option_string(self->player, "keep-open", "yes");
    /* Never allow implicit encoded passthrough: default to decoded PCM.
     * The caller explicitly selects an endpoint and its allowed codec subset.
     * This is an application policy, not an HDMI ELD/receiver verification. */
    status = mpv_set_option_string(self->player, "audio-spdif",
                                   codecs != NULL ? codecs : "");
    if (status >= 0) {
        status = mpv_set_option_string(self->player, "audio-channels",
                                       pcm_channels != NULL ? pcm_channels : "auto-safe");
    }
    if (status >= 0 && device_id != NULL && g_strcmp0(device_id, "auto") != 0) {
        status = mpv_set_option_string(self->player, "audio-device", device_id);
    }
    if (status < 0) {
        mpv_terminate_destroy(self->player);
        self->player = NULL;
        return self;
    }
    /* The default GL framebuffer uses a BT.709/BT.1886 SDR target. An opt-in
     * patched renderer may instead fill a BT.2100/PQ float texture, which GTK
     * must independently label. Neither path proves a native display HDR mode. */
    /* A PQ texture is only meaningful when the owning GTK widget supplies
     * a BT.2100 color state and the patched libmpv renderer is selected.
     * Never force PQ on the default GtkGLArea framebuffer. */
    status = mpv_set_option_string(self->player, "target-prim",
                                   experimental_pq ? "bt.2020" : "bt.709");
    if (status >= 0) {
        status = mpv_set_option_string(self->player, "target-trc",
                                       experimental_pq ? "pq" : "bt.1886");
    }
    if (status >= 0) {
        status = mpv_set_option_string(self->player, "icc-profile-auto",
                                       experimental_pq ? "no" : "yes");
    }
    /* The embedded libmpv GL backend does not expose gpu-next HDR scanout or
     * full Dolby Vision Profile 7 FEL rendering. Use only supported SDR options. */
    if (status >= 0) {
        status = mpv_set_option_string(self->player, "tone-mapping",
                                       tone_mapping != NULL ? tone_mapping : "auto");
    }
    if (status >= 0) {
        status = mpv_set_option_string(self->player, "deband", deband ? "yes" : "no");
    }
    if (status >= 0) {
        status = mpv_initialize(self->player);
    }
    if (status < 0) {
        mpv_terminate_destroy(self->player);
        self->player = NULL;
        return self;
    }
    mpv_observe_property(self->player, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(self->player, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(self->player, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(self->player, 0, "edition-list", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "edition", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "disc-title-list", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "disc-title", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "disc-menu-active", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "track-list", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "chapter-list", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "paused-for-cache", MPV_FORMAT_FLAG);
    mpv_observe_property(self->player, 0, "cache-buffering-state", MPV_FORMAT_INT64);
    mpv_observe_property(self->player, 0, "seeking", MPV_FORMAT_FLAG);
    mpv_observe_property(self->player, 0, "chapter", MPV_FORMAT_INT64);
    mpv_observe_property(self->player, 0, "sub-visibility", MPV_FORMAT_FLAG);
    mpv_observe_property(self->player, 0, "hwdec-current", MPV_FORMAT_STRING);
    mpv_observe_property(self->player, 0, "video-params", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "audio-params", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "audio-out-params", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "current-tracks/audio/codec", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "audio-device", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "current-ao", MPV_FORMAT_NONE);
    mpv_observe_property(self->player, 0, "audio-device-list", MPV_FORMAT_NONE);
    mpv_set_wakeup_callback(self->player, on_mpv_wakeup, self);
#endif
    return self;
}

/** Retains the original SDR constructor ABI for existing applications. */
MediaKitEngine *
mediakit_engine_new_with_audio_and_video(const gchar *device_id, const gchar *codecs,
                                         const gchar *pcm_channels,
                                         const gchar *tone_mapping, gboolean deband)
{
    return mediakit_engine_new_with_video_target(device_id, codecs, pcm_channels,
                                                  tone_mapping, deband, FALSE);
}

/** Preserves the original audio-only constructor and its default SDR behavior. */
MediaKitEngine *
mediakit_engine_new_with_audio(const gchar *device_id, const gchar *codecs,
                                const gchar *pcm_channels)
{
    return mediakit_engine_new_with_audio_and_video(device_id, codecs, pcm_channels,
                                                   "auto", FALSE);
}

/** Maintains the pre-Stage-5 engine construction ABI with safe PCM defaults. */
MediaKitEngine *
mediakit_engine_new(void)
{
    return mediakit_engine_new_with_audio("auto", "", "auto-safe");
}

#ifdef MEDIAKIT_HAVE_MPV
/** Detects the minimum mpv version containing the discnav command. */
static gboolean
supports_disc_menu(mpv_handle *player)
{
    gchar *version = mpv_get_property_string(player, "mpv-version");
    unsigned int major = 0;
    unsigned int minor = 0;
    gboolean supported = FALSE;

    if (version != NULL && sscanf(version, "mpv %u.%u", &major, &minor) == 2) {
        supported = major > 0 || minor >= 42;
    }
    mpv_free(version);
    return supported;
}
#endif

/** Configures a local disc source without interpolating its path into mpv commands. */
gboolean
mediakit_engine_prepare_disc(MediaKitEngine *self, const gchar *kind,
                             const gchar *path, gboolean require_menu, GError **error)
{
    const gchar *option;
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), FALSE);

    if (g_strcmp0(kind, "dvd") == 0) {
        option = "options/dvd-device";
    } else if (g_strcmp0(kind, "bluray") == 0) {
        option = "options/bluray-device";
    } else {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "Unsupported optical-disc kind");
        return FALSE;
    }
    if (path == NULL || !g_path_is_absolute(path) || strlen(path) > 4096 ||
        !g_utf8_validate(path, -1, NULL)) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "Disc device path must be an absolute UTF-8 path");
        return FALSE;
    }
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player != NULL && !self->closing && self->open_task == NULL) {
        gboolean menu_supported = supports_disc_menu(self->player);
        if (require_menu && !menu_supported) {
            g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                                "Disc menus require mpv 0.42 or newer");
            return FALSE;
        }
        int status = mpv_set_property_string(self->player, option, path);
        if (status < 0) {
            set_mpv_error(error, status, "Unable to configure optical disc device");
            return FALSE;
        }
        self->disc_source = TRUE;
        self->disc_menu_supported = menu_supported;
        return TRUE;
    }
#endif
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_INITIALIZED,
                        "No native disc playback engine is available");
    return FALSE;
}

/** Queues a load and retains an asynchronous result until a file-loaded event arrives. */
void
mediakit_engine_load_async(MediaKitEngine *self,
                           const gchar *uri,
                           GCancellable *cancellable,
                           GAsyncReadyCallback callback,
                           gpointer user_data)
{
    GTask *task;
    g_return_if_fail(MEDIAKIT_IS_ENGINE(self));

    task = g_task_new(self, cancellable, callback, user_data);
    g_task_set_source_tag(task, mediakit_engine_load_async);
    if (self->open_task != NULL) {
        g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_PENDING,
                                "A media load is already pending");
        g_object_unref(task);
        return;
    }
    if (cancellable != NULL && g_cancellable_is_cancelled(cancellable)) {
        g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_CANCELLED,
                                "Media loading was canceled");
        g_object_unref(task);
        return;
    }
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player == NULL) {
        g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_FAILED,
                                "libmpv failed to initialize");
        g_object_unref(task);
        return;
    }
    self->open_task = task;
    if (cancellable != NULL) {
        self->cancel_id = g_cancellable_connect(cancellable, G_CALLBACK(on_load_cancelled),
                                               g_object_ref(self), g_object_unref);
    }
    if (self->open_task != NULL) {
        const char *command[] = { "loadfile", uri, "replace", NULL };
        int status = mpv_command_async(self->player, 1, command);
        if (status < 0) {
            complete_open(self, g_error_new(G_IO_ERROR, G_IO_ERROR_FAILED,
                                            "Unable to queue source: %s",
                                            mpv_error_string(status)));
        }
    }
#else
    g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "%s", mediakit_engine_unavailable_reason());
    g_object_unref(task);
#endif
}

/** Propagates an actual asynchronous completion result to the Vala caller. */
gboolean
mediakit_engine_load_finish(MediaKitEngine *self, GAsyncResult *result, GError **error)
{
    g_return_val_if_fail(g_task_is_valid(result, self), FALSE);
    return g_task_propagate_boolean(G_TASK(result), error);
}

#ifdef MEDIAKIT_HAVE_MPV
/** Translates a synchronous nonblocking libmpv property-setting result. */
static gboolean
set_pause(MediaKitEngine *self, gboolean paused, GError **error)
{
    int value = paused ? 1 : 0;
    int status;
    if (self->player == NULL) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_INITIALIZED,
                            "libmpv is not initialized");
        return FALSE;
    }
    status = mpv_set_property_async(self->player, 34, "pause", MPV_FORMAT_FLAG, &value);
    if (status < 0) {
        set_mpv_error(error, status, "Unable to change playback pause state");
        return FALSE;
    }
    return TRUE;
}
#endif

/** Resumes the active source without performing I/O on the GTK main context. */
gboolean
mediakit_engine_play(MediaKitEngine *self, GError **error)
{
#ifdef MEDIAKIT_HAVE_MPV
    return set_pause(self, FALSE, error);
#else
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                        mediakit_engine_unavailable_reason());
    return FALSE;
#endif
}

/** Pauses the active source without closing its decoder or source. */
gboolean
mediakit_engine_pause(MediaKitEngine *self, GError **error)
{
#ifdef MEDIAKIT_HAVE_MPV
    return set_pause(self, TRUE, error);
#else
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                        mediakit_engine_unavailable_reason());
    return FALSE;
#endif
}

/** Stops the timeline at zero while retaining the loaded media source. */
gboolean
mediakit_engine_stop(MediaKitEngine *self, GError **error)
{
#ifdef MEDIAKIT_HAVE_MPV
    if (!set_pause(self, TRUE, error)) {
        return FALSE;
    }
    return mediakit_engine_seek(self, 0, error);
#else
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                        mediakit_engine_unavailable_reason());
    return FALSE;
#endif
}

/** Queues an absolute nonblocking seek using an unambiguous fractional-second value. */
gboolean
mediakit_engine_seek(MediaKitEngine *self, gint64 position_us, GError **error)
{
    if (position_us < 0) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "Seek position must be nonnegative");
        return FALSE;
    }
#ifdef MEDIAKIT_HAVE_MPV
    gchar position[64];
    const char *command[] = { "seek", position, "absolute+exact", NULL };
    int status;
    if (self->player == NULL) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_INITIALIZED,
                            "libmpv is not initialized");
        return FALSE;
    }
    g_ascii_formatd(position, sizeof(position), "%.6f", position_us / 1000000.0);
    status = mpv_command_async(self->player, 33, command);
    if (status < 0) {
        set_mpv_error(error, status, "Unable to seek");
        return FALSE;
    }
    return TRUE;
#else
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                        mediakit_engine_unavailable_reason());
    return FALSE;
#endif
}

#ifdef MEDIAKIT_HAVE_MPV
/** Looks up one named member in an mpv node map without copying its value. */
static const mpv_node *
find_node_member(const mpv_node *node, const gchar *key)
{
    if (node == NULL || node->format != MPV_FORMAT_NODE_MAP) {
        return NULL;
    }
    for (int index = 0; index < node->u.list->num; index++) {
        if (g_strcmp0(node->u.list->keys[index], key) == 0) {
            return &node->u.list->values[index];
        }
    }
    return NULL;
}

/** Reads optional track and chapter string fields without exposing mpv allocations. */
static const gchar *
node_string(const mpv_node *node)
{
    return node != NULL && node->format == MPV_FORMAT_STRING &&
        node->u.string != NULL ? node->u.string : "";
}

/** Converts potentially malformed source tags into bounded, valid UTF-8. */
static gchar *
node_safe_text(const mpv_node *node)
{
    const gchar *source = node_string(node);
    return g_utf8_make_valid(source, strnlen(source, 4096));
}

/** Reads an mpv flag only when it is explicitly present and type-correct. */
static gboolean
node_flag(const mpv_node *node)
{
    return node != NULL && node->format == MPV_FORMAT_FLAG && node->u.flag != 0;
}

/** Converts a source track ID into a stable decimal string for public clients. */
static gchar *
node_track_id(const mpv_node *node)
{
    if (node == NULL) {
        return NULL;
    }
    if (node->format == MPV_FORMAT_INT64) {
        return g_strdup_printf("%" G_GINT64_FORMAT, (gint64)node->u.int64);
    }
    if (node->format == MPV_FORMAT_STRING) {
        return g_strndup(node->u.string, 32);
    }
    return NULL;
}

/** Constructs one metadata snapshot in a stable typed GVariant wire contract. */
static GVariant *
read_metadata(MediaKitEngine *self, const char *property, gboolean chapters)
{
    GVariantBuilder entries;
    mpv_node root = {0};
    g_variant_builder_init(&entries, G_VARIANT_TYPE("aa{sv}"));
    if (self->player == NULL || self->closing ||
        mpv_get_property(self->player, property, MPV_FORMAT_NODE, &root) < 0) {
        return g_variant_ref_sink(g_variant_builder_end(&entries));
    }
    if (root.format == MPV_FORMAT_NODE_ARRAY) {
        int count = MIN(root.u.list->num, chapters ? 1024 : 256);
        for (int index = 0; index < count; index++) {
            const mpv_node *node = &root.u.list->values[index];
            GVariantBuilder entry;
            if (node->format != MPV_FORMAT_NODE_MAP) {
                continue;
            }
            g_variant_builder_init(&entry, G_VARIANT_TYPE_VARDICT);
            if (chapters) {
                const mpv_node *time_node = find_node_member(node, "time");
                double seconds = 0.0;
                if (time_node != NULL && time_node->format == MPV_FORMAT_DOUBLE) {
                    seconds = time_node->u.double_;
                } else if (time_node != NULL && time_node->format == MPV_FORMAT_INT64) {
                    seconds = (double)time_node->u.int64;
                }
                gint64 start_us = 0;
                if (isfinite(seconds) && seconds > 0.0 &&
                    seconds < ((double)G_MAXINT64 / 1000000.0)) {
                    start_us = (gint64)(seconds * 1000000.0);
                }
                g_variant_builder_add(&entry, "{sv}", "index",
                                      g_variant_new_uint32((guint)index));
                g_variant_builder_add(&entry, "{sv}", "start-us",
                                      g_variant_new_int64(start_us));
                gchar *title = node_safe_text(find_node_member(node, "title"));
                g_variant_builder_add(&entry, "{sv}", "title",
                                      g_variant_new_string(title));
                g_free(title);
            } else {
                gchar *id = node_track_id(find_node_member(node, "id"));
                if (id == NULL || *id == '\0') {
                    g_free(id);
                    g_variant_builder_clear(&entry);
                    continue;
                }
                g_variant_builder_add(&entry, "{sv}", "id", g_variant_new_string(id));
                const gchar *names[] = { "type", "codec", "lang", "title", NULL };
                for (int name_index = 0; names[name_index] != NULL; name_index++) {
                    const gchar *name = names[name_index];
                    gchar *safe = node_safe_text(find_node_member(node, name));
                    g_variant_builder_add(&entry, "{sv}", name,
                                          g_variant_new_string(safe));
                    g_free(safe);
                }
                const gchar *flags[] = { "selected", "default", "forced", "external", NULL };
                for (int flag_index = 0; flags[flag_index] != NULL; flag_index++) {
                    const gchar *name = flags[flag_index];
                    g_variant_builder_add(&entry, "{sv}", name,
                        g_variant_new_boolean(node_flag(find_node_member(node, name))));
                }
                g_free(id);
            }
            g_variant_builder_add_value(&entries, g_variant_builder_end(&entry));
        }
    }
    mpv_free_node_contents(&root);
    return g_variant_ref_sink(g_variant_builder_end(&entries));
}
#endif

/** Returns source tracks as an owned array of typed metadata dictionaries. */
GVariant *
mediakit_engine_get_tracks(MediaKitEngine *self)
{
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), NULL);
#ifdef MEDIAKIT_HAVE_MPV
    return read_metadata(self, "track-list", FALSE);
#else
    GVariantBuilder empty;
    g_variant_builder_init(&empty, G_VARIANT_TYPE("aa{sv}"));
    return g_variant_ref_sink(g_variant_builder_end(&empty));
#endif
}

/** Returns source chapters as an owned array of typed metadata dictionaries. */
GVariant *
mediakit_engine_get_chapters(MediaKitEngine *self)
{
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), NULL);
#ifdef MEDIAKIT_HAVE_MPV
    return read_metadata(self, "chapter-list", TRUE);
#else
    GVariantBuilder empty;
    g_variant_builder_init(&empty, G_VARIANT_TYPE("aa{sv}"));
    return g_variant_ref_sink(g_variant_builder_end(&empty));
#endif
}


/** Reports source-specific DVD/Blu-ray title/edition metadata from libmpv. */
GVariant *
mediakit_engine_get_disc_titles(MediaKitEngine *self)
{
    GVariantBuilder titles;
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), NULL);
    g_variant_builder_init(&titles, G_VARIANT_TYPE("aa{sv}"));
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player != NULL && self->disc_source && !self->closing) {
        mpv_node root = {0};
        const gchar *property = self->disc_menu_supported
            ? "edition-list" : "disc-title-list";
        const gchar *selection = self->disc_menu_supported ? "edition" : "disc-title";
        gint64 selected = -1;
        int status = mpv_get_property(self->player, property, MPV_FORMAT_NODE, &root);

        if (status < 0 && self->disc_menu_supported) {
            property = "disc-title-list";
            selection = "disc-title";
            status = mpv_get_property(self->player, property, MPV_FORMAT_NODE, &root);
        }
        mpv_get_property(self->player, selection, MPV_FORMAT_INT64, &selected);
        if (status >= 0) {
            if (root.format == MPV_FORMAT_NODE_ARRAY) {
                int count = MIN(root.u.list->num, 512);
                for (int index = 0; index < count; index++) {
                    const mpv_node *item = &root.u.list->values[index];
                    const mpv_node *duration;
                    double seconds = 0.0;
                    gchar *title;
                    GVariantBuilder entry;
                    if (item->format != MPV_FORMAT_NODE_MAP) {
                        continue;
                    }
                    duration = find_node_member(item, "duration");
                    if (duration != NULL && duration->format == MPV_FORMAT_DOUBLE) {
                        seconds = duration->u.double_;
                    } else if (duration != NULL && duration->format == MPV_FORMAT_INT64) {
                        seconds = (double)duration->u.int64;
                    }
                    if (!isfinite(seconds) || seconds < 0.0 ||
                        seconds >= (double)G_MAXINT64 / 1000000.0) {
                        seconds = 0.0;
                    }
                    title = node_safe_text(find_node_member(item, "title"));
                    g_variant_builder_init(&entry, G_VARIANT_TYPE_VARDICT);
                    g_variant_builder_add(&entry, "{sv}", "index", g_variant_new_uint32(index));
                    g_variant_builder_add(&entry, "{sv}", "title", g_variant_new_string(title));
                    g_variant_builder_add(&entry, "{sv}", "duration-us",
                                          g_variant_new_int64((gint64)(seconds * 1000000.0)));
                    g_variant_builder_add(&entry, "{sv}", "selected",
                                          g_variant_new_boolean(selected == index));
                    g_variant_builder_add_value(&titles, g_variant_builder_end(&entry));
                    g_free(title);
                }
            }
            mpv_free_node_contents(&root);
        }
    }
#endif
    return g_variant_ref_sink(g_variant_builder_end(&titles));
}

/** Advertises menu command capability separately from current visible menu state. */
GVariant *
mediakit_engine_get_disc_status(MediaKitEngine *self)
{
    GVariantBuilder status;
    gboolean supported = FALSE;
    gboolean active = FALSE;
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), NULL);
    g_variant_builder_init(&status, G_VARIANT_TYPE_VARDICT);
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player != NULL && self->disc_source && !self->closing) {
        supported = self->disc_menu_supported;
        if (supported) {
            int flag = 0;
            if (mpv_get_property(self->player, "disc-menu-active", MPV_FORMAT_FLAG,
                                 &flag) >= 0) {
                active = flag != 0;
            }
        }
    }
#endif
    g_variant_builder_add(&status, "{sv}", "menu-supported",
                          g_variant_new_boolean(supported));
    g_variant_builder_add(&status, "{sv}", "menu-active",
                          g_variant_new_boolean(active));
    return g_variant_ref_sink(g_variant_builder_end(&status));
}

/** Selects an existing native disc title using modern or legacy mpv properties. */
gboolean
mediakit_engine_select_disc_title(MediaKitEngine *self, guint index, GError **error)
{
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), FALSE);
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player != NULL && self->disc_source && !self->closing) {
        gchar number[32];
        const gchar *property = self->disc_menu_supported ? "edition" : "disc-title";
        g_snprintf(number, sizeof(number), "%u", index);
        const gchar *command[] = { "set", property, number, NULL };
        int status = mpv_command_async(self->player, 31, command);
        if (status >= 0) {
            return TRUE;
        }
        set_mpv_error(error, status, "Unable to select disc title");
        return FALSE;
    }
#endif
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                        "No active DVD or Blu-ray title can be selected");
    return FALSE;
}

/** Restricts navigation to libmpv 0.42+ discnav commands on active disc sources. */
gboolean
mediakit_engine_navigate_disc_menu(MediaKitEngine *self, const gchar *action,
                                   GError **error)
{
    const gchar *accepted[] = { "up", "down", "left", "right", "select",
                                "prev", "menu", NULL };
    gboolean valid = FALSE;
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), FALSE);
    for (guint index = 0; accepted[index] != NULL; index++) {
        valid |= g_strcmp0(action, accepted[index]) == 0;
    }
    if (!valid) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "Unknown optical disc menu operation");
        return FALSE;
    }
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player != NULL && self->disc_source &&
        self->disc_menu_supported && !self->closing) {
        const char *command[] = { "discnav", action, NULL };
        int status = mpv_command_async(self->player, 31, command);
        if (status >= 0) {
            return TRUE;
        }
        set_mpv_error(error, status, "Unable to navigate disc menu");
        return FALSE;
    }
#endif
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                        "Interactive disc menu navigation is unavailable");
    return FALSE;
}

#ifdef MEDIAKIT_HAVE_MPV
/** Copies only known primitive mpv metadata types into a GLib variant dictionary. */
static void
add_color_field(GVariantBuilder *builder, const mpv_node *root, const char *key)
{
    const mpv_node *field = find_node_member(root, key);

    if (field == NULL) {
        return;
    }
    if (field->format == MPV_FORMAT_STRING && field->u.string != NULL) {
        gchar *safe = node_safe_text(field);
        g_variant_builder_add(builder, "{sv}", key, g_variant_new_string(safe));
        g_free(safe);
    } else if (field->format == MPV_FORMAT_DOUBLE &&
               isfinite(field->u.double_) && field->u.double_ >= 0.0) {
        g_variant_builder_add(builder, "{sv}", key,
                              g_variant_new_double(field->u.double_));
    } else if (field->format == MPV_FORMAT_INT64 && field->u.int64 >= 0) {
        g_variant_builder_add(builder, "{sv}", key,
                              g_variant_new_int64(field->u.int64));
    }
}
#endif

/** Returns a source-color snapshot without claiming any compositor HDR support. */
GVariant *
mediakit_engine_get_video_color(MediaKitEngine *self)
{
    GVariantBuilder metadata;
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), NULL);
    g_variant_builder_init(&metadata, G_VARIANT_TYPE_VARDICT);
#ifdef MEDIAKIT_HAVE_MPV
    mpv_node root = {0};
    if (self->player != NULL && !self->closing &&
        mpv_get_property(self->player, "video-params", MPV_FORMAT_NODE, &root) >= 0) {
        if (root.format == MPV_FORMAT_NODE_MAP) {
            const char *names[] = {
                "primaries", "gamma", "colormatrix", "colorlevels",
                "max-cll", "max-fall", "min-luma", "max-luma",
                "scene-max-r", "scene-max-g", "scene-max-b", NULL
            };
            for (int index = 0; names[index] != NULL; index++) {
                add_color_field(&metadata, &root, names[index]);
            }
        }
        mpv_free_node_contents(&root);
    }
    if (self->player != NULL && !self->closing) {
        gint64 profile = 0;
        if (mpv_get_property(self->player,
                             "current-tracks/video/dolby-vision-profile",
                             MPV_FORMAT_INT64, &profile) >= 0 && profile > 0) {
            g_variant_builder_add(&metadata, "{sv}", "dolby-vision-profile",
                                  g_variant_new_int64(profile));
        }
    }
#endif
    return g_variant_ref_sink(g_variant_builder_end(&metadata));
}

#ifdef MEDIAKIT_HAVE_MPV
/** Reads a bounded string property without leaking libmpv-allocated memory. */
static void
add_audio_property(GVariantBuilder *dictionary, mpv_handle *player,
                   const char *property, const char *name)
{
    char *value = mpv_get_property_string(player, property);
    if (value == NULL) {
        return;
    }
    gchar *safe = g_utf8_make_valid(value, strnlen(value, 4096));
    g_variant_builder_add(dictionary, "{sv}", name, g_variant_new_string(safe));
    g_free(safe);
    mpv_free(value);
}

/** Adds only independently observed stream/output audio parameter fields. */
static void
add_audio_params(GVariantBuilder *dictionary, mpv_handle *player,
                 const char *property, const char *prefix)
{
    mpv_node root = {0};
    if (mpv_get_property(player, property, MPV_FORMAT_NODE, &root) < 0) {
        return;
    }
    if (root.format == MPV_FORMAT_NODE_MAP) {
        const char *keys[] = { "format", "channels", "channel-count", "samplerate" };
        const char *suffix[] = { "format", "layout", "channels", "rate" };
        for (guint index = 0; index < G_N_ELEMENTS(keys); index++) {
            const mpv_node *value = find_node_member(&root, keys[index]);
            if (value == NULL) {
                continue;
            }
            gchar *name = g_strdup_printf("%s-%s", prefix, suffix[index]);
            if (value->format == MPV_FORMAT_STRING) {
                gchar *safe = node_safe_text(value);
                g_variant_builder_add(dictionary, "{sv}", name, g_variant_new_string(safe));
                g_free(safe);
            } else if (value->format == MPV_FORMAT_INT64 && value->u.int64 >= 0) {
                g_variant_builder_add(dictionary, "{sv}", name,
                                      g_variant_new_int64(value->u.int64));
            }
            g_free(name);
        }
    }
    mpv_free_node_contents(&root);
}
#endif

/** Returns source and actual output metadata without claiming receiver capabilities. */
GVariant *
mediakit_engine_get_audio_information(MediaKitEngine *self)
{
    GVariantBuilder dictionary;
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), NULL);
    g_variant_builder_init(&dictionary, G_VARIANT_TYPE_VARDICT);
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player != NULL && !self->closing) {
        add_audio_property(&dictionary, self->player, "current-tracks/audio/codec", "source-codec");
        add_audio_property(&dictionary, self->player, "audio-device", "device");
        add_audio_property(&dictionary, self->player, "current-ao", "driver");
        add_audio_params(&dictionary, self->player, "audio-params", "source");
        add_audio_params(&dictionary, self->player, "audio-out-params", "output");
    }
#endif
    return g_variant_ref_sink(g_variant_builder_end(&dictionary));
}

/** Enumerates mpv audio outputs; formats supported by each device are unknown. */
GVariant *
mediakit_engine_get_audio_devices(MediaKitEngine *self)
{
    GVariantBuilder devices;
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), NULL);
    g_variant_builder_init(&devices, G_VARIANT_TYPE("aa{sv}"));
#ifdef MEDIAKIT_HAVE_MPV
    mpv_node root = {0};
    if (self->player != NULL && !self->closing &&
        mpv_get_property(self->player, "audio-device-list", MPV_FORMAT_NODE, &root) >= 0) {
        if (root.format == MPV_FORMAT_NODE_ARRAY) {
            int count = MIN(root.u.list->num, 256);
            for (int index = 0; index < count; index++) {
                const mpv_node *item = &root.u.list->values[index];
                if (item->format != MPV_FORMAT_NODE_MAP) {
                    continue;
                }
                gchar *name = node_safe_text(find_node_member(item, "name"));
                gchar *description = node_safe_text(find_node_member(item, "description"));
                if (*name != '\0') {
                    GVariantBuilder entry;
                    g_variant_builder_init(&entry, G_VARIANT_TYPE_VARDICT);
                    g_variant_builder_add(&entry, "{sv}", "id", g_variant_new_string(name));
                    g_variant_builder_add(&entry, "{sv}", "description",
                                          g_variant_new_string(description));
                    g_variant_builder_add_value(&devices, g_variant_builder_end(&entry));
                }
                g_free(name);
                g_free(description);
            }
        }
        mpv_free_node_contents(&root);
    }
#endif
    return g_variant_ref_sink(g_variant_builder_end(&devices));
}

/** Queues output-device selection; actual output is observed independently. */
gboolean
mediakit_engine_select_audio_device(MediaKitEngine *self,
                                    const gchar *device_id,
                                    GError **error)
{
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), FALSE);
    if (device_id == NULL || *device_id == '\0' ||
        strlen(device_id) > 256 || !g_utf8_validate(device_id, -1, NULL)) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "Invalid audio output device identifier");
        return FALSE;
    }
    for (const gchar *cursor = device_id; *cursor != '\0'; cursor++) {
        if ((guchar)*cursor < 32 || (guchar)*cursor == 127) {
            g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                                "Audio output device ID contains a control character");
            return FALSE;
        }
    }
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player != NULL && !self->closing) {
        char *value = (char *)device_id;
        int status = mpv_set_property_async(self->player, 35, "audio-device",
                                            MPV_FORMAT_STRING, &value);
        if (status >= 0) {
            return TRUE;
        }
        set_mpv_error(error, status, "Unable to select audio device");
        return FALSE;
    }
#endif
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_INITIALIZED,
                        "The playback engine is unavailable");
    return FALSE;
}

/** Queues one validated track selection using libmpv's public property command. */
gboolean
mediakit_engine_select_track(MediaKitEngine *self, const gchar *kind,
                             const gchar *id, GError **error)
{
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), FALSE);
    const gchar *property = NULL;
    if (g_strcmp0(kind, "video") == 0) {
        property = "vid";
    } else if (g_strcmp0(kind, "audio") == 0) {
        property = "aid";
    } else if (g_strcmp0(kind, "subtitle") == 0) {
        property = "sid";
    } else {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "Unknown track category");
        return FALSE;
    }
    if (id != NULL) {
        if (*id == '\0' || strlen(id) > 20) {
            g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                                "Track ID is empty or too long");
            return FALSE;
        }
        for (const gchar *cursor = id; *cursor != '\0'; cursor++) {
            if (!g_ascii_isdigit(*cursor)) {
                g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                                    "Track ID must be a decimal integer");
                return FALSE;
            }
        }
    }
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player != NULL && !self->closing) {
        const char *command[] = { "set", property, id != NULL ? id : "no", NULL };
        int status = mpv_command_async(self->player, 31, command);
        if (status >= 0) {
            return TRUE;
        }
        set_mpv_error(error, status, "Unable to select media track");
        return FALSE;
    }
#endif
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_INITIALIZED,
                        "The playback engine is unavailable");
    return FALSE;
}

/** Navigates to a zero-based chapter using libmpv's chapter property. */
gboolean
mediakit_engine_select_chapter(MediaKitEngine *self, guint index, GError **error)
{
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), FALSE);
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player != NULL && !self->closing) {
        gchar chapter[32];
        g_snprintf(chapter, sizeof(chapter), "%u", index);
        const char *command[] = { "set", "chapter", chapter, NULL };
        int status = mpv_command_async(self->player, 31, command);
        if (status >= 0) {
            return TRUE;
        }
        set_mpv_error(error, status, "Unable to navigate to chapter");
        return FALSE;
    }
#endif
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_INITIALIZED,
                        "The playback engine is unavailable");
    return FALSE;
}

/** Requests renderer subtitle visibility without changing the selected track. */
gboolean
mediakit_engine_set_subtitles_visible(MediaKitEngine *self, gboolean visible,
                                      GError **error)
{
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), FALSE);
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player != NULL && !self->closing) {
        int flag = visible ? 1 : 0;
        int status = mpv_set_property_async(self->player, 32,
                                            "sub-visibility", MPV_FORMAT_FLAG, &flag);
        if (status >= 0) {
            return TRUE;
        }
        set_mpv_error(error, status, "Unable to change subtitle visibility");
        return FALSE;
    }
#endif
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_INITIALIZED,
                        "The playback engine is unavailable");
    return FALSE;
}

/** Invalidates pending results and stops a source without destroying the player handle. */
void
mediakit_engine_close(MediaKitEngine *self)
{
    g_return_if_fail(MEDIAKIT_IS_ENGINE(self));
    self->closing = TRUE;
    if (self->open_task != NULL) {
        complete_open(self, g_error_new_literal(G_IO_ERROR, G_IO_ERROR_CANCELLED,
                                                "The playback session was closed"));
    }
#ifdef MEDIAKIT_HAVE_MPV
    if (self->player != NULL) {
        const char *command[] = { "stop", NULL };
        mpv_command_async(self->player, 0, command);
    }
#endif
}

/** Tests only the build-selected libmpv ABI, not GPU or monitor capability. */
gboolean
mediakit_engine_has_experimental_gpu_next(void)
{
#ifdef MEDIAKIT_EXPERIMENTAL_EMBEDDED_GPU_NEXT
    return TRUE;
#else
    return FALSE;
#endif
}

/** Attaches the current host OpenGL context using the explicitly selected API. */
static MediaKitRenderer *
create_renderer_with_mode(MediaKitEngine *self, gboolean experimental, GError **error)
{
#ifdef MEDIAKIT_HAVE_MPV
    mpv_opengl_init_params init = { .get_proc_address = resolve_gl, .get_proc_address_ctx = NULL };
    mpv_render_param params[4] = {
        { MPV_RENDER_PARAM_API_TYPE, (void *)MPV_RENDER_API_TYPE_OPENGL },
        { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &init },
        { MPV_RENDER_PARAM_INVALID, NULL },
        { MPV_RENDER_PARAM_INVALID, NULL }
    };
    MediaKitRenderer *renderer;
    int status;

    if (self->player == NULL || self->active_renderer != NULL) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_BUSY,
                            "An initialized engine and one unused video renderer are required");
        return NULL;
    }
    if (experimental) {
#ifdef MEDIAKIT_EXPERIMENTAL_EMBEDDED_GPU_NEXT
        /* Only the patched ABI exposes this parameter; it is never guessed. */
        params[2] = (mpv_render_param){ MPV_RENDER_PARAM_BACKEND, (void *)"gpu-next" };
#else
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "Experimental embedded gpu-next was not built; "
                            "use the standard OpenGL renderer or the Wayland player");
        return NULL;
#endif
    }
    renderer = g_object_new(MEDIAKIT_TYPE_RENDERER, NULL);
    renderer->engine = g_object_ref(self);
    status = mpv_render_context_create(&renderer->render_context, self->player, params);
    if (status < 0) {
        set_mpv_error(error, status,
                      experimental ? "Patched embedded gpu-next failed"
                                   : "Could not initialize embedded OpenGL video output");
        g_object_unref(renderer);
        return NULL;
    }
    renderer->experimental_gpu_next = experimental;
    self->active_renderer = renderer;
    mpv_render_context_set_update_callback(renderer->render_context,
                                           on_render_update, renderer);
    return renderer;
#else
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                        mediakit_engine_unavailable_reason());
    return NULL;
#endif
}

/** Preserves the original stable OpenGL API and its existing behavior. */
MediaKitRenderer *
mediakit_engine_create_renderer(MediaKitEngine *self, GError **error)
{
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), NULL);
    return create_renderer_with_mode(self, FALSE, error);
}

/** Selects experimental gpu-next only on builds explicitly compiled for it. */
MediaKitRenderer *
mediakit_engine_create_renderer_gpu_next(MediaKitEngine *self, GError **error)
{
    g_return_val_if_fail(MEDIAKIT_IS_ENGINE(self), NULL);
    return create_renderer_with_mode(self, TRUE, error);
}

/** Emits render requests only on the creating main context. */
static void
mediakit_renderer_init(MediaKitRenderer *self)
{
    self->context = g_main_context_ref_thread_default();
}

/** Releases the unique mpv GL context while the application GL context is current. */
void
mediakit_renderer_release(MediaKitRenderer *self)
{
    g_return_if_fail(MEDIAKIT_IS_RENDERER(self));
    if (self->released) {
        return;
    }
    self->released = TRUE;
#ifdef MEDIAKIT_HAVE_MPV
    if (self->render_context != NULL) {
        mpv_render_context_set_update_callback(self->render_context, NULL, NULL);
        mpv_render_context_free(self->render_context);
        self->render_context = NULL;
    }
#endif
    if (self->engine != NULL) {
        if (self->engine->active_renderer == self) {
            self->engine->active_renderer = NULL;
        }
        g_clear_object(&self->engine);
    }
}

/** Releases any unreleased GPU resources and the thread-default context. */
static void
mediakit_renderer_dispose(GObject *object)
{
    MediaKitRenderer *self = MEDIAKIT_RENDERER(object);
    mediakit_renderer_release(self);
    G_OBJECT_CLASS(mediakit_renderer_parent_class)->dispose(object);
}

/** Finalizes the renderer-owned main-context reference. */
static void
mediakit_renderer_finalize(GObject *object)
{
    MediaKitRenderer *self = MEDIAKIT_RENDERER(object);
    g_clear_pointer(&self->context, g_main_context_unref);
    G_OBJECT_CLASS(mediakit_renderer_parent_class)->finalize(object);
}

/** Registers the frame-ready event for GTK4-driven presentation. */
static void
mediakit_renderer_class_init(MediaKitRendererClass *klass)
{
    GObjectClass *object_class = G_OBJECT_CLASS(klass);
    object_class->dispose = mediakit_renderer_dispose;
    object_class->finalize = mediakit_renderer_finalize;
    renderer_update_signal = g_signal_new("update-requested", G_TYPE_FROM_CLASS(klass),
        G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL, G_TYPE_NONE, 0);
}

/** Applies or clears an ICC profile without changing the source metadata. */
gboolean
mediakit_renderer_set_icc_profile(MediaKitRenderer *self, GBytes *profile, GError **error)
{
    g_return_val_if_fail(MEDIAKIT_IS_RENDERER(self), FALSE);
    if (self->released) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_CLOSED,
                            "Cannot update a released OpenGL renderer");
        return FALSE;
    }
#ifdef MEDIAKIT_HAVE_MPV
    gsize size = 0;
    const guint8 *bytes = NULL;
    mpv_byte_array blob = {0};
    int status;

    if (profile != NULL) {
        bytes = g_bytes_get_data(profile, &size);
        /* Only reasonably sized ICC profiles with a standard header are passed
         * to the GPU library; avoid unbounded memory or arbitrary file blobs. */
        if (size < 128 || size > 4 * 1024 * 1024 ||
            bytes == NULL || memcmp(bytes + 36, "acsp", 4) != 0) {
            g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_DATA,
                                "Display ICC profile is invalid or too large");
            return FALSE;
        }
    }
    blob.data = (void *)bytes;
    blob.size = size;
    status = mpv_render_context_set_parameter(self->render_context,
                                               MPV_RENDER_PARAM_ICC_PROFILE, &blob);
    if (status < 0) {
        set_mpv_error(error, status, "Unable to configure display ICC profile");
        return FALSE;
    }
    self->icc_profile_active = profile != NULL;
    return TRUE;
#else
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                        mediakit_engine_unavailable_reason());
    return FALSE;
#endif
}

/** Reports measured framebuffer precision without inferring actual HDR display output. */
GVariant *
mediakit_renderer_get_output_information(MediaKitRenderer *self)
{
    GVariantBuilder builder;
    g_return_val_if_fail(MEDIAKIT_IS_RENDERER(self), NULL);

    g_variant_builder_init(&builder, G_VARIANT_TYPE_VARDICT);
    if (!self->released) {
#ifdef MEDIAKIT_HAVE_MPV
        g_variant_builder_add(&builder, "{sv}", "backend",
                              g_variant_new_string(self->experimental_gpu_next
                                                   ? "libmpv-gpu-next-experimental"
                                                   : "libmpv-opengl"));
#endif
        g_variant_builder_add(&builder, "{sv}", "red-bits",
                              g_variant_new_int32(self->red_bits));
        g_variant_builder_add(&builder, "{sv}", "green-bits",
                              g_variant_new_int32(self->green_bits));
        g_variant_builder_add(&builder, "{sv}", "blue-bits",
                              g_variant_new_int32(self->blue_bits));
        g_variant_builder_add(&builder, "{sv}", "render-depth-bits",
                              g_variant_new_int32(self->render_depth_bits));
        g_variant_builder_add(&builder, "{sv}", "icc-active",
                              g_variant_new_boolean(self->icc_profile_active));
        g_variant_builder_add(&builder, "{sv}", "frame-submitted",
                              g_variant_new_boolean(self->frame_submitted));
    }
    return g_variant_ref_sink(g_variant_builder_end(&builder));
}

/** Invalidates bound-framebuffer metadata after a host reallocates GL buffers. */
void
mediakit_renderer_invalidate_framebuffer(MediaKitRenderer *self)
{
    g_return_if_fail(MEDIAKIT_IS_RENDERER(self));
    self->framebuffer_information_valid = FALSE;
}

#ifdef MEDIAKIT_HAVE_MPV
/** Validates the attached floating-point color buffer without trusting its label. */
static gboolean
validate_pq_framebuffer(MediaKitRenderer *self, GLint framebuffer, GError **error)
{
    if (framebuffer == 0 || glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) !=
                            GL_FRAMEBUFFER_COMPLETE) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "PQ output requires a complete non-default framebuffer");
        return FALSE;
    }
    GLint component_type = 0;
    GLint red_bits = 0;
    GLint green_bits = 0;
    GLint blue_bits = 0;
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                           GL_FRAMEBUFFER_ATTACHMENT_COMPONENT_TYPE,
                                           &component_type);
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                           GL_FRAMEBUFFER_ATTACHMENT_RED_SIZE, &red_bits);
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                           GL_FRAMEBUFFER_ATTACHMENT_GREEN_SIZE, &green_bits);
    glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                           GL_FRAMEBUFFER_ATTACHMENT_BLUE_SIZE, &blue_bits);
    if (glGetError() != GL_NO_ERROR || component_type != GL_FLOAT ||
        red_bits < 16 || green_bits < 16 || blue_bits < 16) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "PQ output requires a verified RGB16F color attachment");
        return FALSE;
    }
    self->red_bits = red_bits;
    self->green_bits = green_bits;
    self->blue_bits = blue_bits;
    self->last_framebuffer = framebuffer;
    self->framebuffer_information_valid = TRUE;
    return TRUE;
}
#endif

/** Renders into the current framebuffer with a strictly selected color contract. */
static gboolean
render_with_target(MediaKitRenderer *self, gint width_px, gint height_px,
                   gboolean pq_target, GError **error)
{
    g_return_val_if_fail(MEDIAKIT_IS_RENDERER(self), FALSE);
    if (self->released || width_px <= 0 || height_px <= 0) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "Renderer is detached or its framebuffer size is invalid");
        return FALSE;
    }
#ifdef MEDIAKIT_HAVE_MPV
    if (self->render_context == NULL) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_INITIALIZED,
                            "No active libmpv render context");
        return FALSE;
    }
    if (pq_target && (!self->experimental_gpu_next || self->engine == NULL ||
                      !self->engine->pq_output_requested)) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "PQ output requires the patched renderer and PQ-configured engine");
        return FALSE;
    }
    if (!pq_target && self->engine != NULL &&
        self->engine->pq_output_requested) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "PQ pixels must use render_pq and a tagged float texture");
        return FALSE;
    }
    GLint framebuffer = 0;
    int flip_y = 1;
    int depth = 8;
    mpv_opengl_fbo fbo;
    mpv_render_param params[4];
    int status;
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &framebuffer);
    if (pq_target && !validate_pq_framebuffer(self, framebuffer, error)) {
        return FALSE;
    }
    /* Query the channel precision only after a target change or invalidation. */
    if (!self->framebuffer_information_valid || self->last_framebuffer != framebuffer) {
        GLint red_bits = 0;
        GLint green_bits = 0;
        GLint blue_bits = 0;
        glGetIntegerv(GL_RED_BITS, &red_bits);
        glGetIntegerv(GL_GREEN_BITS, &green_bits);
        glGetIntegerv(GL_BLUE_BITS, &blue_bits);
        self->red_bits = MAX(red_bits, 0);
        self->green_bits = MAX(green_bits, 0);
        self->blue_bits = MAX(blue_bits, 0);
        self->last_framebuffer = framebuffer;
        self->framebuffer_information_valid = TRUE;
    }
    if (self->red_bits > 0 && self->green_bits > 0 && self->blue_bits > 0) {
        depth = MIN(self->red_bits, MIN(self->green_bits, self->blue_bits));
    }
    if (pq_target && depth < 16) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "PQ framebuffer bit depth is insufficient");
        return FALSE;
    }
    fbo.fbo = framebuffer;
    fbo.w = width_px;
    fbo.h = height_px;
    /* Zero preserves the stable GtkGLArea path. HDR passes its *actual*
     * float attachment format instead of relying on libmpv's default. */
    fbo.internal_format = pq_target ? GL_RGBA16F : 0;
    params[0] = (mpv_render_param){ MPV_RENDER_PARAM_OPENGL_FBO, &fbo };
    params[1] = (mpv_render_param){ MPV_RENDER_PARAM_FLIP_Y, &flip_y };
    params[2] = (mpv_render_param){ MPV_RENDER_PARAM_DEPTH, &depth };
    params[3] = (mpv_render_param){ MPV_RENDER_PARAM_INVALID, NULL };
    mpv_render_context_update(self->render_context);
    status = mpv_render_context_render(self->render_context, params);
    if (status < 0) {
        set_mpv_error(error, status, "Unable to render video frame");
        return FALSE;
    }
    self->render_depth_bits = depth;
    self->frame_submitted = TRUE;
    return TRUE;
#else
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                        mediakit_engine_unavailable_reason());
    return FALSE;
#endif
}

/** Preserves the original stable SDR render contract and C ABI. */
gboolean
mediakit_renderer_render(MediaKitRenderer *self, gint width_px,
                         gint height_px, GError **error)
{
    return render_with_target(self, width_px, height_px, FALSE, error);
}

/** Uses only a verified RGBA16F target and the experimental gpu-next context. */
gboolean
mediakit_renderer_render_pq(MediaKitRenderer *self, gint width_px,
                            gint height_px, GError **error)
{
    return render_with_target(self, width_px, height_px, TRUE, error);
}
