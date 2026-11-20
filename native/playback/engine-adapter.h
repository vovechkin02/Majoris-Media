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

/** mediakit_engine_new_with_audio:
 * @device_id: Exact mpv output identifier, or "auto" for system default.
 * @codecs: Canonical comma-separated user-approved IEC 61937 codecs, or empty.
 * @pcm_channels: "auto-safe" or explicit source-preferred "auto".
 *
 * Configures audio policy before mpv initialization. The caller must validate
 * codec identifiers and receiver compatibility; a successful configuration
 * is not proof of physical receiver decoding.
 * Returns: (transfer full): New native playback engine.
 */
MediaKitEngine *mediakit_engine_new_with_audio(const gchar *device_id,
                                               const gchar *codecs,
                                               const gchar *pcm_channels);

/** mediakit_engine_new_with_audio_and_video:
 * @device_id: Selected native device ID or "auto".
 * @codecs: Explicit IEC 61937 allowlist, or an empty string.
 * @pcm_channels: Engine-compatible PCM layout policy.
 * @tone_mapping: Validated, legacy-OpenGL-compatible SDR mapping name.
 * @deband: Whether to enable a bounded GPU debanding pass.
 *
 * All video options must be configured before mpv_initialize. Native HDR
 * and gpu-next presentation are not exposed by this API.
 * Returns: (transfer full): New engine, whose open may fail if initialization fails.
 */
MediaKitEngine *mediakit_engine_new_with_audio_and_video(const gchar *device_id,
                                                         const gchar *codecs,
                                                         const gchar *pcm_channels,
                                                         const gchar *tone_mapping,
                                                         gboolean deband);

/** mediakit_engine_new_with_video_target:
 * @device_id: Audio endpoint ID or auto.
 * @codecs: Validated audio passthrough allowlist.
 * @pcm_channels: Selected decoded PCM channel policy.
 * @tone_mapping: Validated mpv tone-map setting.
 * @deband: Enable bounded GPU debanding.
 * @experimental_pq: Request BT.2020/PQ rendering with a patched gpu-next GL API.
 *
 * The PQ option is rejected by the build without an experimental backend. It
 * configures texture pixels only, not Wayland HDR transport or monitor scanout.
 * Returns: (transfer full): New engine; opening fails when unavailable.
 */
MediaKitEngine *mediakit_engine_new_with_video_target(const gchar *device_id,
                                                       const gchar *codecs,
                                                       const gchar *pcm_channels,
                                                       const gchar *tone_mapping,
                                                       gboolean deband,
                                                       gboolean experimental_pq);

/** mediakit_engine_get_audio_information:
 * @self: Operational playback engine.
 *
 * Returns: (transfer full): Typed `a{sv}` containing separately observed source
 * and output properties; missing values remain absent.
 */
GVariant *mediakit_engine_get_audio_information(MediaKitEngine *self);

/** mediakit_engine_get_audio_devices:
 * @self: Operational playback engine.
 *
 * Returns: (transfer full): `aa{sv}` device ID and label inventory. No codec
 * capability is implied by an enumerated output device.
 */
GVariant *mediakit_engine_get_audio_devices(MediaKitEngine *self);

/** mediakit_engine_select_audio_device:
 * @self: Operational playback engine.
 * @device_id: Exact enumerated mpv device ID or "auto".
 * @error: (out) (optional): Immediate submission failure.
 *
 * Asynchronous rejection is reported via operation-failed.
 * Returns: TRUE when the device change was queued, not confirmed.
 */
gboolean mediakit_engine_select_audio_device(MediaKitEngine *self,
                                                const gchar *device_id,
                                                GError **error);

/** mediakit_engine_prepare_disc:
 * @self: Operational engine before loading a disc.
 * @kind: Exactly "dvd" or "bluray".
 * @path: Absolute local device path, directory, or ISO image filename.
 * @require_menu: Whether opening requires mpv 0.42+ menu handling.
 * @error: (out) (optional): Unsupported menu or invalid device/path.
 *
 * Sets a separate mpv disc-device option; callers must not concatenate paths
 * into synthetic disc URLs. This operation does not attempt AACS decryption.
 * Returns: TRUE when the device selection is accepted.
 */
gboolean mediakit_engine_prepare_disc(MediaKitEngine *self,
                                       const gchar *kind,
                                       const gchar *path,
                                       gboolean require_menu,
                                       GError **error);

/** mediakit_engine_get_disc_titles:
 * @self: Active native engine.
 *
 * Returns: (transfer full): `aa{sv}` disc title/edition snapshots; may be empty.
 */
GVariant *mediakit_engine_get_disc_titles(MediaKitEngine *self);

/** mediakit_engine_get_disc_status:
 * @self: Active native engine.
 *
 * Returns: (transfer full): `a{sv}` with menu support/activity separately.
 */
GVariant *mediakit_engine_get_disc_status(MediaKitEngine *self);

/** mediakit_engine_select_disc_title:
 * @self: Active native engine.
 * @index: Zero-based, discovered title/edition index.
 * @error: (out) (optional): Invalid selection or unsupported source.
 *
 * Returns: TRUE when the selection has been queued; watch for metadata events.
 */
gboolean mediakit_engine_select_disc_title(MediaKitEngine *self, guint index,
                                            GError **error);

/** mediakit_engine_navigate_disc_menu:
 * @self: Active native engine.
 * @action: Exact validated action from the backend's closed vocabulary.
 * @error: (out) (optional): Unsupported menu or invalid action.
 *
 * Returns: TRUE when the nonblocking command was queued, not when acted upon.
 */
gboolean mediakit_engine_navigate_disc_menu(MediaKitEngine *self,
                                             const gchar *action,
                                             GError **error);

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

/** mediakit_engine_has_experimental_gpu_next:
 *
 * Returns: TRUE only when compiled against the separately enabled, patched
 * libmpv OpenGL gpu-next API. Does not establish native HDR display support.
 */
gboolean mediakit_engine_has_experimental_gpu_next(void);

/** mediakit_engine_create_renderer_gpu_next:
 * @self: Engine with an initialized libmpv context.
 * @error: (out) (optional): Unsupported API or render-context failure.
 *
 * Explicitly selects the unmerged gpu-next OpenGL backend with the patched
 * MPV_RENDER_PARAM_BACKEND parameter. Never silently switches to legacy GL.
 * Only one attached renderer is allowed and a current GL context is required.
 * Returns: (transfer full) (nullable): Renderer, or NULL with an error.
 */
MediaKitRenderer *mediakit_engine_create_renderer_gpu_next(MediaKitEngine *self,
                                                           GError **error);

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

/** mediakit_renderer_invalidate_framebuffer:
 * @self: Live renderer on the owning GL context.
 *
 * Forces channel-precision remeasurement on the next render, for a GTK
 * framebuffer reallocation or output configuration change.
 */
void mediakit_renderer_invalidate_framebuffer(MediaKitRenderer *self);

/** mediakit_renderer_get_output_information:
 * @self: Live GL-thread renderer with a currently bound framebuffer.
 *
 * Returns observed GL channel precision, the submitted render parameter, and
 * accepted ICC configuration as an a{sv} snapshot. This information does not
 * establish compositor colorspace, HDR scanout, or Dolby Vision reconstruction.
 * Returns: (transfer full): Caller-owned GVariant dictionary.
 */
GVariant *mediakit_renderer_get_output_information(MediaKitRenderer *self);

/** mediakit_renderer_release:
 * @self: Renderer being detached on its owning OpenGL context.
 *
 * Idempotently releases native GPU resources; call before GLArea unrealize.
 */
void mediakit_renderer_release(MediaKitRenderer *self);

G_END_DECLS

#endif
