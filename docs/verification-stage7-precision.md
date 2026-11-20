# Stage 7.5 verification — float framebuffer and output policy

**Version:** 0.7.5
**Status:** Source implementation; not compiled or hardware-qualified here.
**Date:** 2026-11-21

## Changes in this pass

1. A separate `render_pq` operation passes the **actual** `GL_RGBA16F`
   attachment format to the patched libmpv render interface. The pre-existing
   SDR render call remains in place with the same ABI and `internal_format=0`.
2. Native rendering validates a complete, non-default draw framebuffer, floating
   RGB component type and at least 16 bits per color channel. PQ calls reject
   non-patched engines and engines not explicitly created for PQ output; SDR
   calls reject PQ-configured engines. There is no automatic downgraded output.
3. The GTK offscreen frame bridge now checks GPU dimensions, allocation,
   synchronization and texture publication errors. It restores separate
   OpenGL read/draw framebuffer bindings. Rendering failure discards the cached
   texture to avoid showing a stale frame as if playback were still working.
4. Source-only HDR classification no longer calls a PQ stream HDR10+ simply
   because a scene peak is present. HDR10+ requires an explicit confirmation
   signal. The current native source adapter does **not** provide that signal;
   no HDR10+ detection capability is claimed for this engine build.
5. Capability reporting distinguishes patched API build support (`UNVERIFIED`)
   from an unavailable backend; neither status establishes actual display HDR.

## Verification performed

- **Passed:** `tools/check_structure.py` (XML, Meson inventory and Core/GTK split).
- **Passed:** `tools/check_source_docs.py` (handwritten declarations checked).
- **Passed:** ZIP integrity and executable permissions (checked after packaging).
- **Not run:** `meson setup`, Vala/C compilation and GObject introspection.
- **Not run:** runtime GTK renderer tests, Wayland HDR output, colorimetric
  analysis, 4K GPU performance and Dolby Vision Profile 7 MEL/FEL comparisons.

The authoring environment has no Meson, valac, GTK4 development libraries,
libmpv development libraries or libepoxy development libraries, and Debian
package repositories were not reachable. Static tests must not be represented
as a successful native build or as verified playback.

## Build and qualification requirements

Use a normal Debian 13 environment first, with Vala, Meson, libgtk-4-dev,
libmpv-dev, libepoxy-dev, libjson-glib-dev and libglib2.0-dev installed:

```sh
meson setup build -Dgtk=true -Dmpv=enabled -Dtests=true \
  -Dexperimental_embedded_gpu_next=false -Dexperimental_gtk_pq=false
meson compile -C build
meson test -C build --print-errorlogs
```

Then build separately against **matching patched** libmpv headers and runtime
based on the upstream draft rendering API, never against an arbitrary
unverified ABI:

```sh
PKG_CONFIG_PATH=/path/to/patched/lib/pkgconfig \
meson setup build-hdr -Dgtk=true -Dmpv=enabled -Dtests=true \
  -Dexperimental_embedded_gpu_next=true -Dexperimental_gtk_pq=true
meson compile -C build-hdr
meson test -C build-hdr --print-errorlogs
```

Run the patched widget on a supported Wayland/GNOME system with a real HDR
monitor and a separate output-signal verification method. Test actual PQ
luminance, pixel color, SDR fallback, source replacement, GPU context loss,
4K memory pressure and renderer lifetime. For Dolby Vision Profile 7 FEL,
compare known-reference base and enhancement-layer decoded outputs; a DV
profile flag or successful GPU rendering is insufficient. HDR10+/Dolby Vision
display-link dynamic signaling is not implemented by the GDK color-state tag.

**Release status:** The remainder of Stage 7 that requires a stable embedding
API, actual HDR display negotiation, licensed dynamic HDR signaling or hardware
FEL testing is **not completed** by this patch. Do not enable experimental
embedding in the default Debian or Majoris ISO package.
