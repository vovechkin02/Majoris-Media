#ifndef MEDIAKIT_HDR_FRAME_H
#define MEDIAKIT_HDR_FRAME_H

#include <gdk/gdk.h>

G_BEGIN_DECLS

typedef struct _MediaKitHdrFrame MediaKitHdrFrame;

/** mediakit_hdr_frame_new:
 * @context: (transfer none): Initialized GL context owned by the host widget.
 * Returns: (transfer full): Frame target retaining its GL context.
 */
MediaKitHdrFrame *mediakit_hdr_frame_new(GdkGLContext *context);

/** mediakit_hdr_frame_begin:
 * @self: Owning frame target.
 * @width_px: Width in physical pixels.
 * @height_px: Height in physical pixels.
 * @error: (out) (optional): Error if RGBA16F framebuffer is unavailable.
 * Returns: TRUE if the private framebuffer was bound successfully.
 */
gboolean mediakit_hdr_frame_begin(MediaKitHdrFrame *self, gint width_px,
                                   gint height_px, GError **error);

/** mediakit_hdr_frame_finish:
 * @self: Frame begun on the current GL context.
 * @error: (out) (optional): Error on invalid lifecycle state.
 * Returns: (transfer full): Immutable, BT.2100/PQ-tagged GTK GL texture.
 */
GdkTexture *mediakit_hdr_frame_finish(MediaKitHdrFrame *self, GError **error);

/** mediakit_hdr_frame_abort:
 * @self: Frame target holding or not holding an in-progress GL framebuffer.
 * Restores previous GL state and discards any unfinished frame.
 */
void mediakit_hdr_frame_abort(MediaKitHdrFrame *self);

/** mediakit_hdr_frame_free:
 * @self: (transfer full): Frame target whose owner is being destroyed.
 * Releases the frame bridge; completed GTK textures remain independently owned.
 */
void mediakit_hdr_frame_free(MediaKitHdrFrame *self);

G_END_DECLS

#endif
