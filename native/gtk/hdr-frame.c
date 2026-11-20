#include "hdr-frame.h"

#include <epoxy/gl.h>

#include "hdr-frame-budget.h"
#include "hdr-frame-format.h"

/* A GdkGLTexture is immutable while GTK may reference it. One completed
 * frame owns one GL texture. The compositor may retain earlier textures even
 * after the widget replaces its snapshot, so bound all outstanding RGBA16F
 * frames instead of assuming a single widget-side reference is sufficient. */
#define MAX_IN_FLIGHT_HDR_FRAMES 3

struct _MediaKitHdrFrame {
    GdkGLContext *context;
    GLuint texture;
    GLuint framebuffer;
    GLint previous_framebuffer;
    GLint previous_read_framebuffer;
    GLint previous_viewport[4];
    GLint previous_scissor_box[4];
    GLint previous_blend_src_rgb;
    GLint previous_blend_dst_rgb;
    GLint previous_blend_src_alpha;
    GLint previous_blend_dst_alpha;
    GLfloat previous_clear_color[4];
    GLboolean previous_scissor_enabled;
    GLboolean previous_blend_enabled;
    gboolean state_saved;
    gint width_px;
    gint height_px;
    MediaKitHdrFrameBudget *budget;
    gboolean slot_reserved;
};

typedef struct {
    GdkGLContext *context;
    GLuint texture;
    GLsync sync;
    MediaKitHdrFrameBudget *budget;
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
    mediakit_hdr_frame_budget_release(retired->budget);
    mediakit_hdr_frame_budget_unref(retired->budget);
    g_free(retired);
}

/** Retains the host GL context without starting any rendering. */
MediaKitHdrFrame *
mediakit_hdr_frame_new(GdkGLContext *context)
{
    g_return_val_if_fail(GDK_IS_GL_CONTEXT(context), NULL);
    MediaKitHdrFrame *self = g_new0(MediaKitHdrFrame, 1);
    self->context = g_object_ref(context);
    self->budget = mediakit_hdr_frame_budget_new(MAX_IN_FLIGHT_HDR_FRAMES);
    if (self->budget == NULL) {
        g_clear_object(&self->context);
        g_free(self);
        return NULL;
    }
    return self;
}

/** Saves the OpenGL state that libmpv explicitly does not promise to preserve. */
static void
save_host_gl_state(MediaKitHdrFrame *self)
{
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &self->previous_framebuffer);
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &self->previous_read_framebuffer);
    glGetIntegerv(GL_VIEWPORT, self->previous_viewport);
    glGetIntegerv(GL_SCISSOR_BOX, self->previous_scissor_box);
    glGetIntegerv(GL_BLEND_SRC_RGB, &self->previous_blend_src_rgb);
    glGetIntegerv(GL_BLEND_DST_RGB, &self->previous_blend_dst_rgb);
    glGetIntegerv(GL_BLEND_SRC_ALPHA, &self->previous_blend_src_alpha);
    glGetIntegerv(GL_BLEND_DST_ALPHA, &self->previous_blend_dst_alpha);
    glGetFloatv(GL_COLOR_CLEAR_VALUE, self->previous_clear_color);
    self->previous_scissor_enabled = glIsEnabled(GL_SCISSOR_TEST);
    self->previous_blend_enabled = glIsEnabled(GL_BLEND);
    self->state_saved = TRUE;
}

/** Restores GTK's framebuffer and caller GL state after libmpv rendering. */
static void
restore_host_gl_state(MediaKitHdrFrame *self)
{
    if (!self->state_saved) {
        return;
    }
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, self->previous_framebuffer);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, self->previous_read_framebuffer);
    glViewport(self->previous_viewport[0], self->previous_viewport[1],
               self->previous_viewport[2], self->previous_viewport[3]);
    glScissor(self->previous_scissor_box[0], self->previous_scissor_box[1],
              self->previous_scissor_box[2], self->previous_scissor_box[3]);
    glBlendFuncSeparate(self->previous_blend_src_rgb, self->previous_blend_dst_rgb,
                        self->previous_blend_src_alpha, self->previous_blend_dst_alpha);
    glClearColor(self->previous_clear_color[0], self->previous_clear_color[1],
                 self->previous_clear_color[2], self->previous_clear_color[3]);
    if (self->previous_scissor_enabled) {
        glEnable(GL_SCISSOR_TEST);
    } else {
        glDisable(GL_SCISSOR_TEST);
    }
    if (self->previous_blend_enabled) {
        glEnable(GL_BLEND);
    } else {
        glDisable(GL_BLEND);
    }
    self->state_saved = FALSE;
}

/** Checks texture allocation against the actual GPU storage, not requested GL format. */
static gboolean
verify_gpu_float_texture(GLuint texture)
{
    MediaKitHdrPixelFormat format = {0};
    GLint prior_binding = 0;
    GLint value = 0;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &prior_binding);
    glBindTexture(GL_TEXTURE_2D, texture);

    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_INTERNAL_FORMAT, &value);
    format.internal_format = (uint32_t)value;
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_RED_TYPE, &value);
    format.red_type = (uint32_t)value;
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_GREEN_TYPE, &value);
    format.green_type = (uint32_t)value;
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_BLUE_TYPE, &value);
    format.blue_type = (uint32_t)value;
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_ALPHA_TYPE, &value);
    format.alpha_type = (uint32_t)value;
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_RED_SIZE, &format.red_bits);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_GREEN_SIZE, &format.green_bits);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_BLUE_SIZE, &format.blue_bits);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_ALPHA_SIZE, &format.alpha_bits);

    GLenum status = glGetError();
    glBindTexture(GL_TEXTURE_2D, (GLuint)prior_binding);
    return status == GL_NO_ERROR &&
           mediakit_hdr_pixel_format_is_rgba16f(&format, GL_RGBA16F, GL_FLOAT);
}

/** Allocates a bounded, offscreen RGBA16F render target without CPU readback. */
gboolean
mediakit_hdr_frame_begin(MediaKitHdrFrame *self, gint width_px,
                          gint height_px, GError **error)
{
    g_return_val_if_fail(self != NULL, FALSE);
    if (self->slot_reserved || self->texture != 0 || self->framebuffer != 0) {
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
    /* The patched OpenGL libmpv backend requires desktop GL. In particular,
     * this path uses glGetTexLevelParameteriv to verify the actual storage. */
    if (gdk_gl_context_get_api(self->context) != GDK_GL_API_GL) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "Experimental HDR requires a desktop OpenGL context");
        return FALSE;
    }
    gint gl_major = 0;
    gint gl_minor = 0;
    gdk_gl_context_get_version(self->context, &gl_major, &gl_minor);
    if (gl_major < 3 || (gl_major == 3 && gl_minor < 2)) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "HDR float textures require OpenGL 3.2 or newer");
        return FALSE;
    }
    /* Respect both READ and DRAW framebuffer bindings; they may differ in GTK. */
    GLint previous_texture = 0;
    GLint maximum_texture_size = 0;
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maximum_texture_size);
    if (width_px > maximum_texture_size || height_px > maximum_texture_size) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "HDR frame exceeds the GPU's maximum texture dimension");
        return FALSE;
    }
    if (!mediakit_hdr_frame_budget_try_acquire(self->budget)) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_WOULD_BLOCK,
                            "The compositor is retaining too many HDR frames");
        return FALSE;
    }
    self->slot_reserved = TRUE;
    save_host_gl_state(self);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &previous_texture);
    /* libmpv expects these default states for an independently owned FBO.
     * GTK's previous state is restored before its snapshot resumes. */
    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_BLEND);
    glGenTextures(1, &self->texture);
    if (self->texture == 0) {
        mediakit_hdr_frame_abort(self);
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NO_SPACE,
                            "Unable to allocate an HDR texture");
        return FALSE;
    }
    glBindTexture(GL_TEXTURE_2D, self->texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width_px, height_px,
                 0, GL_RGBA, GL_HALF_FLOAT, NULL);
    GLenum texture_error = glGetError();
    glBindTexture(GL_TEXTURE_2D, (GLuint) previous_texture);
    if (texture_error != GL_NO_ERROR) {
        mediakit_hdr_frame_abort(self);
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NO_SPACE,
                            "The GPU rejected the RGBA16F texture allocation");
        return FALSE;
    }
    if (!verify_gpu_float_texture(self->texture)) {
        mediakit_hdr_frame_abort(self);
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "The GPU did not allocate an actual RGBA16F floating-point texture");
        return FALSE;
    }
    glGenFramebuffers(1, &self->framebuffer);
    if (self->framebuffer == 0) {
        mediakit_hdr_frame_abort(self);
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                            "Unable to allocate the HDR framebuffer");
        return FALSE;
    }
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
    if (sync == NULL) {
        mediakit_hdr_frame_abort(self);
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                            "GPU synchronization unavailable for HDR texture sharing");
        return NULL;
    }
    glFlush();
    restore_host_gl_state(self);
    glDeleteFramebuffers(1, &self->framebuffer);
    self->framebuffer = 0;

    RetiredTexture *retired = g_new0(RetiredTexture, 1);
    retired->context = g_object_ref(self->context);
    retired->texture = self->texture;
    retired->sync = sync;
    retired->budget = mediakit_hdr_frame_budget_ref(self->budget);
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
    self->slot_reserved = FALSE;  /* The GdkTexture release callback now owns the slot. */
    GdkTexture *texture = gdk_gl_texture_builder_build(
        builder, retired_texture_destroy, retired);
    g_object_unref(builder);
    if (texture == NULL) {
        retired_texture_destroy(retired);
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                            "GTK rejected the color-tagged HDR texture");
        return NULL;
    }
    /* Verify the object GTK actually accepted instead of treating the
     * requested builder values as evidence of a correct color-state tag. */
    if (gdk_texture_get_format(texture) !=
            GDK_MEMORY_R16G16B16A16_FLOAT_PREMULTIPLIED ||
        !gdk_color_state_equal(gdk_texture_get_color_state(texture),
                               gdk_color_state_get_rec2100_pq())) {
        g_object_unref(texture);  /* Invokes the resource release callback. */
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "GTK did not retain the RGB16F BT.2100/PQ texture contract");
        return NULL;
    }
    return texture;
}

/** Releases a partially rendered frame, restoring the previous GL target. */
void
mediakit_hdr_frame_abort(MediaKitHdrFrame *self)
{
    g_return_if_fail(self != NULL);
    if (!self->slot_reserved && self->framebuffer == 0 && self->texture == 0) {
        return;
    }
    gdk_gl_context_make_current(self->context);
    if (gdk_gl_context_get_current() == self->context) {
        restore_host_gl_state(self);
        if (self->framebuffer != 0) {
            glDeleteFramebuffers(1, &self->framebuffer);
        }
        if (self->texture != 0) {
            glDeleteTextures(1, &self->texture);
        }
    }
    self->framebuffer = 0;
    self->texture = 0;
    self->state_saved = FALSE;
    if (self->slot_reserved) {
        self->slot_reserved = FALSE;
        mediakit_hdr_frame_budget_release(self->budget);
    }
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
    mediakit_hdr_frame_budget_unref(self->budget);
    g_free(self);
}
