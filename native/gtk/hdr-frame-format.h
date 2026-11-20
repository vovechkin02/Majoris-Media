#ifndef MEDIAKIT_HDR_FRAME_FORMAT_H
#define MEDIAKIT_HDR_FRAME_FORMAT_H

#include <stdbool.h>
#include <stdint.h>

/* Internal symbols must not extend the public MediaKit C ABI. */
#if defined(__GNUC__) || defined(__clang__)
#define MEDIAKIT_HDR_FORMAT_PRIVATE __attribute__((visibility("hidden")))
#else
#define MEDIAKIT_HDR_FORMAT_PRIVATE
#endif

/* GL enum identities are intentionally supplied by the caller. This private
 * C11 contract is testable without a GL context, GLib, GTK, or a GPU driver. */
typedef struct {
    uint32_t internal_format;
    uint32_t red_type;
    uint32_t green_type;
    uint32_t blue_type;
    uint32_t alpha_type;
    int red_bits;
    int green_bits;
    int blue_bits;
    int alpha_bits;
} MediaKitHdrPixelFormat;

/** Accepts only an actual four-channel floating-point 16-bit GL texture.
 * @actual: Driver-reported texture information, not application-supplied tags.
 * @required_format: GL_RGBA16F from the current GL implementation.
 * @floating_type: GL_FLOAT from the current GL implementation.
 * Returns: TRUE only when all components retain the advertised precision.
 */
MEDIAKIT_HDR_FORMAT_PRIVATE bool mediakit_hdr_pixel_format_is_rgba16f(
    const MediaKitHdrPixelFormat *actual,
    uint32_t required_format,
    uint32_t floating_type);

#endif
