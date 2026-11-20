#include "hdr-frame-format.h"

#include <stddef.h>

/** Validates the *driver's* GL storage, independent of the GTK color tag. */
bool
mediakit_hdr_pixel_format_is_rgba16f(const MediaKitHdrPixelFormat *actual,
                                     uint32_t required_format,
                                     uint32_t floating_type)
{
    if (actual == NULL || actual->internal_format != required_format) {
        return false;
    }

    return actual->red_type == floating_type &&
           actual->green_type == floating_type &&
           actual->blue_type == floating_type &&
           actual->alpha_type == floating_type &&
           actual->red_bits == 16 && actual->green_bits == 16 &&
           actual->blue_bits == 16 && actual->alpha_bits == 16;
}
