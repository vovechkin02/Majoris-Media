#include "hdr-frame.h"

#include <epoxy/gl.h>

/* A GdkGLTexture is immutable while GTK may reference it. One completed
 * frame owns one GL texture. The Gtk widget holds and reuses the last frame
 * between actual libmpv updates rather than allocating per snapshot. */
struct _MediaKitHdrFrame {
    GdkGLContext *context;
    GLuint texture;
    GLuint framebuffer;
    GLint previous_framebuffer;
    GLint previous_viewport[4];
    gint width_px;
    gint height_px;
};

typedef struct {
    GdkGLContext *context;
    GLuint texture;
    GLsync sync;
} RetiredTexture;

/** Releases texture storage when its last GdkTexture user releases it. */
static void
retired_texture_destroy(gpointer user_data)
{
    RetiredTexture *retired = user_data;
    gdk_gl_context_make_current(retired->context);
    if (gdk_gl_context_get_current() == retired->context) {
        if (retired->sync != NULL) {
            glDeleteSync(retired->sync);
        }
        glDeleteTextures(1, &retired->texture);
    }
    g_clear_object(&retired->context);
    g_free(retired);
}

/** Retains the host GL context without starting any rendering. */
MediaKitHdrFrame *
mediakit_hdr_frame_new(GdkGLContext *context)
{
    g_return_val_if_fail(GDK_IS_GL_CONTEXT(context), NULL);
    MediaKitHdrFrame *self = g_new0(MediaKitHdrFrame, 1);
    self->context = g_object_ref(context);
    return self;
}

/** Allocates a bounded, offscreen RGBA16F render target without CPU readback. */
gboolean
mediakit_hdr_frame_begin(MediaKitHdrFrame *self, gint width_px,
                          gint height_px, GError **error)
{
    g_return_val_if_fail(self != NULL, FALSE);
    if (self->texture != 0 || self->framebuffer != 0) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_PENDING,
                            "An HDR frame is already in progress");
        return FALSE;
    }
    if (width_px <= 0 || height_px <= 0 || width_px > 4096 || height_px > 2304) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "PQ target must not exceed 4096 x 2304 pixels");
        return FALSE;
    }
    gdk_gl_context_make_current(self->context);
    if (gdk_gl_context_get_current() != self->context) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                            "The HDR GL context could not be made current");
        return FALSE;
    }
    GLint previous_texture = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &self->previous_framebuffer);
    glGetIntegerv(GL_VIEWPORT, self->previous_viewport);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &previous_texture);
    glGenTextures(1, &self->texture);
    glBindTexture(GL_TEXTURE_2D, self->texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width_px, height_px,
                 0, GL_RGBA, GL_HALF_FLOAT, NULL);
    glBindTexture(GL_TEXTURE_2D, (GLuint) previous_texture);
    glGenFramebuffers(1, &self->framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, self->framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, self->texture, 0);
    self->width_px = width_px;
    self->height_px = height_px;
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        mediakit_hdr_frame_abort(self);
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "The current GL context does not support RGBA16F output");
        return FALSE;
    }
    glViewport(0, 0, width_px, height_px);
    return TRUE;
}

/** Transfers the completed framebuffer's GL texture to GTK as PQ pixels. */
GdkTexture *
mediakit_hdr_frame_finish(MediaKitHdrFrame *self, GError **error)
{
    g_return_val_if_fail(self != NULL, NULL);
    if (self->texture == 0 || self->framebuffer == 0) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "No HDR frame is in progress");
        return NULL;
    }
    /* GTK may sample this texture from another shared GL context. An explicit
     * fence accompanies the image so GTK can synchronize without glFinish. */
    GLsync sync = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    glFlush();
    glBindFramebuffer(GL_FRAMEBUFFER, self->previous_framebuffer);
    glViewport(self->previous_viewport[0], self->previous_viewport[1],
               self->previous_viewport[2], self->previous_viewport[3]);
    glDeleteFramebuffers(1, &self->framebuffer);
    self->framebuffer = 0;

    RetiredTexture *retired = g_new0(RetiredTexture, 1);
    retired->context = g_object_ref(self->context);
    retired->texture = self->texture;
    retired->sync = sync;
    GdkGLTextureBuilder *builder = gdk_gl_texture_builder_new();
    gdk_gl_texture_builder_set_context(builder, self->context);
    gdk_gl_texture_builder_set_id(builder, self->texture);
    gdk_gl_texture_builder_set_width(builder, self->width_px);
    gdk_gl_texture_builder_set_height(builder, self->height_px);
    gdk_gl_texture_builder_set_format(
        builder, GDK_MEMORY_R16G16B16A16_FLOAT_PREMULTIPLIED);
    gdk_gl_texture_builder_set_color_state(
        builder, gdk_color_state_get_rec2100_pq());
    if (sync != NULL) {
        gdk_gl_texture_builder_set_sync(builder, sync);
    }
    self->texture = 0;
    GdkTexture *texture = gdk_gl_texture_builder_build(
        builder, retired_texture_destroy, retired);
    g_object_unref(builder);
    return texture;
}

/** Releases a partially rendered frame, restoring the previous GL target. */
void
mediakit_hdr_frame_abort(MediaKitHdrFrame *self)
{
    g_return_if_fail(self != NULL);
    if (self->framebuffer == 0 && self->texture == 0) {
        return;
    }
    gdk_gl_context_make_current(self->context);
    if (gdk_gl_context_get_current() == self->context) {
        glBindFramebuffer(GL_FRAMEBUFFER, self->previous_framebuffer);
        glViewport(self->previous_viewport[0], self->previous_viewport[1],
                   self->previous_viewport[2], self->previous_viewport[3]);
        if (self->framebuffer != 0) {
            glDeleteFramebuffers(1, &self->framebuffer);
        }
        if (self->texture != 0) {
            glDeleteTextures(1, &self->texture);
        }
    }
    self->framebuffer = 0;
    self->texture = 0;
}

/** Releases unpublished GPU resources while preserving already-published textures. */
void
mediakit_hdr_frame_free(MediaKitHdrFrame *self)
{
    if (self == NULL) {
        return;
    }
    mediakit_hdr_frame_abort(self);
    g_clear_object(&self->context);
    g_free(self);
}
