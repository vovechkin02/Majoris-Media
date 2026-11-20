#include "hdr-frame-format.h"

/* Meson release builds may set NDEBUG; test assertions must still execute. */
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stddef.h>

/* Khronos-defined enum values, used only by this toolchain-independent test. */
#define TEST_GL_RGBA16F 0x881aU
#define TEST_GL_FLOAT 0x1406U
#define TEST_GL_UNSIGNED_BYTE 0x1401U

/** Checks that a full RGBA16F driver report is accepted without GTK. */
static void
test_float_pixel_format(void)
{
    MediaKitHdrPixelFormat actual = {
        .internal_format = TEST_GL_RGBA16F,
        .red_type = TEST_GL_FLOAT,
        .green_type = TEST_GL_FLOAT,
        .blue_type = TEST_GL_FLOAT,
        .alpha_type = TEST_GL_FLOAT,
        .red_bits = 16,
        .green_bits = 16,
        .blue_bits = 16,
        .alpha_bits = 16,
    };
    assert(mediakit_hdr_pixel_format_is_rgba16f(&actual, TEST_GL_RGBA16F,
                                                  TEST_GL_FLOAT));
    assert(!mediakit_hdr_pixel_format_is_rgba16f(NULL, TEST_GL_RGBA16F,
                                                   TEST_GL_FLOAT));

    /* A driver returning fewer bits, a packed/normalized value, or an
     * unexpected internal format must never be labeled RGBA16F/PQ. */
    actual.alpha_bits = 8;
    assert(!mediakit_hdr_pixel_format_is_rgba16f(&actual, TEST_GL_RGBA16F,
                                                   TEST_GL_FLOAT));
    actual.alpha_bits = 16;
    actual.green_type = TEST_GL_UNSIGNED_BYTE;
    assert(!mediakit_hdr_pixel_format_is_rgba16f(&actual, TEST_GL_RGBA16F,
                                                   TEST_GL_FLOAT));
    actual.green_type = TEST_GL_FLOAT;
    actual.internal_format = 0x8058U; /* GL_RGBA8 */
    assert(!mediakit_hdr_pixel_format_is_rgba16f(&actual, TEST_GL_RGBA16F,
                                                   TEST_GL_FLOAT));
}

/** Runs the exact pixel-format contract relied upon by HDR texture handoff. */
int
main(void)
{
    test_float_pixel_format();
    return 0;
}
