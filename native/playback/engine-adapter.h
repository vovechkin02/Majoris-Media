#ifndef MEDIA_ENGINE_ADAPTER_H
#define MEDIA_ENGINE_ADAPTER_H

#include <gio/gio.h>

G_BEGIN_DECLS

#define MEDIAKIT_TYPE_ENGINE (mediakit_engine_get_type())
G_DECLARE_FINAL_TYPE(MediaKitEngine, mediakit_engine, MEDIAKIT, ENGINE, GObject)

#define MEDIAKIT_TYPE_RENDERER (mediakit_renderer_get_type())
G_DECLARE_FINAL_TYPE(MediaKitRenderer, mediakit_renderer, MEDIAKIT, RENDERER, GObject)

/** mediakit_engine_is_available:
 *
 * Returns: TRUE when the optional libmpv integration was compiled in.
 */
gboolean mediakit_engine_is_available(void);

/** mediakit_engine_unavailable_reason:
 *
 * Returns: (transfer none): Stable diagnostic for builds without libmpv.
 */
const gchar *mediakit_engine_unavailable_reason(void);

/** mediakit_engine_new:
 *
 * Returns: (transfer full): Independent native playback engine.
 */
MediaKitEngine *mediakit_engine_new(void);

/** mediakit_engine_load_async:
 * @self: Engine for one playback session.
 * @uri: Validated file, HTTP, or HTTPS URI.
 * @cancellable: (nullable): Operation cancellation.
 * @callback: (scope async): Completion notification.
 * @user_data: (closure callback): Completion context.
 *
 * Completes on FILE_LOADED, command failure, or cancellation, not on queueing.
 */
void mediakit_engine_load_async(MediaKitEngine *self,
                                const gchar *uri,
                                GCancellable *cancellable,
                                GAsyncReadyCallback callback,
                                gpointer user_data);

/** mediakit_engine_load_finish:
 * @self: Engine that initiated the load.
 * @result: The matching asynchronous result.
 * @error: (out) (optional): Error on failure.
 *
 * Returns: TRUE after an actual file-loaded event.
 */
gboolean mediakit_engine_load_finish(MediaKitEngine *self,
                                     GAsyncResult *result,
                                     GError **error);

/** mediakit_engine_play:
 * @self: Playback engine.
 * @error: (out) (optional): Error on failure.
 *
 * Returns: TRUE when unpause was accepted.
 */
gboolean mediakit_engine_play(MediaKitEngine *self, GError **error);

/** mediakit_engine_pause:
 * @self: Playback engine.
 * @error: (out) (optional): Error on failure.
 *
 * Returns: TRUE when pause was accepted.
 */
gboolean mediakit_engine_pause(MediaKitEngine *self, GError **error);

/** mediakit_engine_stop:
 * @self: Playback engine.
 * @error: (out) (optional): Error on failure.
 *
 * Returns: TRUE when stop was accepted.
 */
gboolean mediakit_engine_stop(MediaKitEngine *self, GError **error);

/** mediakit_engine_seek:
 * @self: Playback engine.
 * @position_us: Nonnegative requested position in microseconds.
 * @error: (out) (optional): Error on failure.
 *
 * Returns: TRUE when a seek command was accepted.
 */
gboolean mediakit_engine_seek(MediaKitEngine *self,
                               gint64 position_us,
                               GError **error);

/** mediakit_engine_get_tracks:
 * @self: Active playback engine.
 *
 * Returns: (transfer full): Structured `aa{sv}` track metadata snapshot.
 * The caller owns the returned variant. An empty array indicates no tracks.
 */
GVariant *mediakit_engine_get_tracks(MediaKitEngine *self);

/** mediakit_engine_get_chapters:
 * @self: Active playback engine.
 *
 * Returns: (transfer full): Structured `aa{sv}` chapter metadata snapshot.
 */
GVariant *mediakit_engine_get_chapters(MediaKitEngine *self);

/** mediakit_engine_get_video_color:
 * @self: Active playback engine.
 *
 * Returns: (transfer full): `a{sv}` with typed source color metadata.
 * Unknown or unsupported fields are omitted rather than guessed.
 */
GVariant *mediakit_engine_get_video_color(MediaKitEngine *self);

/** mediakit_engine_select_track:
 * @self: Active playback engine.
 * @kind: One of video, audio or subtitle.
 * @id: (nullable): Valid decimal track id, or NULL to disable that stream.
 * @error: (out) (optional): Immediate command-queue failure.
 *
 * Returns: TRUE if the selection request was queued (not yet confirmed).
 */
gboolean mediakit_engine_select_track(MediaKitEngine *self,
                                      const gchar *kind,
                                      const gchar *id,
                                      GError **error);

/** mediakit_engine_select_chapter:
 * @self: Active playback engine.
 * @index: Zero-based chapter index.
 * @error: (out) (optional): Immediate command-queue failure.
 *
 * Returns: TRUE if the chapter navigation command was queued.
 */
gboolean mediakit_engine_select_chapter(MediaKitEngine *self,
                                        guint index,
                                        GError **error);

/** mediakit_engine_set_subtitles_visible:
 * @self: Active playback engine.
 * @visible: Requested subtitle visibility, separate from track selection.
 * @error: (out) (optional): Immediate command-queue failure.
 *
 * Returns: TRUE when the change request was queued.
 */
gboolean mediakit_engine_set_subtitles_visible(MediaKitEngine *self,
                                                gboolean visible,
                                                GError **error);

/** mediakit_engine_close:
 * @self: Engine whose pending operations must be canceled.
 *
 * Releases the active source; the object itself is reference counted.
 */
void mediakit_engine_close(MediaKitEngine *self);

/** mediakit_engine_create_renderer:
 * @self: Operational engine.
 * @error: (out) (optional): Error if creation fails.
 *
 * Requires a current OpenGL context. Only one renderer may be active per engine.
 * Returns: (transfer full) (nullable): Renderer to be disposed on its GL thread.
 */
MediaKitRenderer *mediakit_engine_create_renderer(MediaKitEngine *self, GError **error);

/** mediakit_renderer_render:
 * @self: Renderer attached to the current OpenGL context.
 * @width_px: Positive target framebuffer width.
 * @height_px: Positive target framebuffer height.
 * @error: (out) (optional): Error on failure.
 *
 * Draws into the currently bound GL framebuffer on the owning GL thread.
 * Returns: TRUE if a frame was successfully submitted.
 */
gboolean mediakit_renderer_render(MediaKitRenderer *self,
                                  gint width_px,
                                  gint height_px,
                                  GError **error);

/** mediakit_renderer_set_icc_profile:
 * @self: Current GL-thread renderer.
 * @profile: (nullable): Complete ICC profile blob, or NULL to clear it.
 * @error: (out) (optional): Invalid ICC input or libmpv rejection.
 *
 * Profile selection belongs to the host/monitor integration; it is not
 * inferred from the source. Call with the GLArea context current.
 * Returns: TRUE when the profile update is accepted by libmpv.
 */
gboolean mediakit_renderer_set_icc_profile(MediaKitRenderer *self,
                                            GBytes *profile,
                                            GError **error);

/** mediakit_renderer_release:
 * @self: Renderer being detached on its owning OpenGL context.
 *
 * Idempotently releases native GPU resources; call before GLArea unrealize.
 */
void mediakit_renderer_release(MediaKitRenderer *self);

G_END_DECLS

#endif
