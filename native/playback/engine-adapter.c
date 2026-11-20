#include "engine-adapter.h"

#include <stdint.h>
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
    gint pending_event_dispatch;
    struct _MediaKitRenderer *active_renderer;
    gboolean closing;
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
            complete_open(self, NULL);
            break;
        case MPV_EVENT_COMMAND_REPLY:
            if (self->open_task != NULL && event->reply_userdata == 1 &&
                event->error < 0) {
                complete_open(self, g_error_new(G_IO_ERROR, G_IO_ERROR_FAILED,
                                                "Unable to load media: %s",
                                                mpv_error_string(event->error)));
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
            if (property == NULL || property->data == NULL) {
                break;
            }
            if (g_strcmp0(property->name, "pause") == 0 &&
                property->format == MPV_FORMAT_FLAG) {
                gboolean paused = *(int *)property->data != 0;
                g_signal_emit(self, engine_signals[SIGNAL_PAUSE_CHANGED], 0, paused);
            } else if (g_strcmp0(property->name, "time-pos") == 0 &&
                       property->format == MPV_FORMAT_DOUBLE) {
                gint64 position_us = (gint64)(*(double *)property->data * 1000000.0);
                if (position_us < 0) {
                    position_us = 0;
                }
                if (llabs(position_us - self->last_position_us) >= 100000) {
                    self->last_position_us = position_us;
                    g_signal_emit(self, engine_signals[SIGNAL_POSITION_CHANGED], 0,
                                  position_us);
                }
            } else if (g_strcmp0(property->name, "duration") == 0 &&
                       property->format == MPV_FORMAT_DOUBLE) {
                gint64 duration_us = (gint64)(*(double *)property->data * 1000000.0);
                g_signal_emit(self, engine_signals[SIGNAL_DURATION_CHANGED], 0,
                              MAX((gint64)0, duration_us));
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
}

/** Allocates and initializes one libmpv handle without touching video GL resources. */
MediaKitEngine *
mediakit_engine_new(void)
{
    MediaKitEngine *self = g_object_new(MEDIAKIT_TYPE_ENGINE, NULL);
#ifdef MEDIAKIT_HAVE_MPV
    int status;
    self->player = mpv_create();
    if (self->player == NULL) {
        return self;
    }
    mpv_set_option_string(self->player, "vo", "libmpv");
    mpv_set_option_string(self->player, "hwdec", "auto-safe");
    mpv_set_option_string(self->player, "terminal", "no");
    mpv_set_option_string(self->player, "pause", "yes");
    mpv_set_option_string(self->player, "keep-open", "yes");
    status = mpv_initialize(self->player);
    if (status < 0) {
        mpv_terminate_destroy(self->player);
        self->player = NULL;
        return self;
    }
    mpv_observe_property(self->player, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(self->player, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(self->player, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_set_wakeup_callback(self->player, on_mpv_wakeup, self);
#endif
    return self;
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
    status = mpv_set_property_async(self->player, 0, "pause", MPV_FORMAT_FLAG, &value);
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
    status = mpv_command_async(self->player, 0, command);
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

/** Attaches the current OpenGL context as the unique native video renderer. */
MediaKitRenderer *
mediakit_engine_create_renderer(MediaKitEngine *self, GError **error)
{
#ifdef MEDIAKIT_HAVE_MPV
    mpv_opengl_init_params init = { .get_proc_address = resolve_gl, .get_proc_address_ctx = NULL };
    mpv_render_param params[] = {
        { MPV_RENDER_PARAM_API_TYPE, (void *)MPV_RENDER_API_TYPE_OPENGL },
        { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &init },
        { MPV_RENDER_PARAM_INVALID, NULL }
    };
    MediaKitRenderer *renderer;
    int status;
    if (self->player == NULL || self->active_renderer != NULL) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_BUSY,
                            "An initialized engine and one unused video renderer are required");
        return NULL;
    }
    renderer = g_object_new(MEDIAKIT_TYPE_RENDERER, NULL);
    renderer->engine = g_object_ref(self);
    status = mpv_render_context_create(&renderer->render_context, self->player, params);
    if (status < 0) {
        set_mpv_error(error, status, "Could not initialize embedded OpenGL video output");
        g_object_unref(renderer);
        return NULL;
    }
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

/** Draws into a GTK GLArea-owned framebuffer without CPU frame copies. */
gboolean
mediakit_renderer_render(MediaKitRenderer *self,
                         gint width_px,
                         gint height_px,
                         GError **error)
{
    if (self->released || width_px <= 0 || height_px <= 0) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "Renderer is detached or its framebuffer size is invalid");
        return FALSE;
    }
#ifdef MEDIAKIT_HAVE_MPV
    GLint framebuffer = 0;
    int flip_y = 1;
    mpv_opengl_fbo fbo;
    mpv_render_param params[3];
    int status;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &framebuffer);
    fbo.fbo = framebuffer;
    fbo.w = width_px;
    fbo.h = height_px;
    fbo.internal_format = 0;
    params[0] = (mpv_render_param){ MPV_RENDER_PARAM_OPENGL_FBO, &fbo };
    params[1] = (mpv_render_param){ MPV_RENDER_PARAM_FLIP_Y, &flip_y };
    params[2] = (mpv_render_param){ MPV_RENDER_PARAM_INVALID, NULL };
    mpv_render_context_update(self->render_context);
    status = mpv_render_context_render(self->render_context, params);
    if (status < 0) {
        set_mpv_error(error, status, "Unable to render video frame");
        return FALSE;
    }
    return TRUE;
#else
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                        mediakit_engine_unavailable_reason());
    return FALSE;
#endif
}
