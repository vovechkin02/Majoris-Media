# Stage 7.6 verification — HDR texture ownership

**Date:** 2026-11-21
**Source baseline:** Majoris Media 0.7.5 supplied ZIP
**Result:** Source-level implementation and standalone C11 safety test complete;
full Stage 7 rendering and hardware qualification **not complete**.

## Implemented in 0.7.6

- Separate `native/gtk/hdr-frame-budget.[ch]` from GTK/GDK code, using C11
  atomics for in-flight texture accounting and lifetime references.
- At most three outstanding RGBA16F frames per experimental view. Acquire a
  slot before the GPU allocation; return it on every aborted frame or through
  the GTK GL texture release callback after publication.
- Keep the frame budget alive independently of the widget while GTK retains
  finished textures, and limit new allocations on a stalled compositor.
- Treat transient `G_IO_ERROR_WOULD_BLOCK` as recoverable: preserve the
  previously submitted texture and retry on a subsequent playback update.
- Verify the accepted `GdkTexture` format and BT.2100/PQ tag before treating
  a frame as successfully handed to GTK.
- Preserve `MediaKit` Core, regular SDR `MediaView`, opt-in experimental Meson
  switches, media session interfaces, and the separate-window gpu-next path.

## Executed checks

| Check | Status | Scope |
| --- | --- | --- |
| GCC C11 unit and concurrency test (`-Wall -Wextra -Werror -O2 -pthread`) | Passed, repeated three times | Atomic cap, release, concurrent operation, ref lifetime |
| Source/structure/XML check | Passed | File inventories, templates, Core/GTK separation and text hygiene |
| Declaration documentation check | Passed | Handwritten Vala/C definitions (714/714) |
| Stage 7 source assets | Present | Existing HDR10 and multi-stream fixtures retained |

## Not run / not demonstrated

- **Full Meson/Vala, GTK4 and libmpv native build:** not run; the authoring
  environment has no `valac` or `meson` and does not have required
  GLib/GTK4/libmpv development headers; network package retrieval fails.
- **Actual GTK HDR texture handoff:** not run (requires GTK 4.16+, OpenGL,
  supported compositor and patched libmpv headers/runtime).
- **Native HDR monitor presentation:** not verified. GDK's PQ tag may be
  converted by the compositor rather than sent to a native HDR output.
- **Dolby Vision Profile 7 FEL:** reconstruction and actual picture quality
  not verified. A source-profile flag or upstream support claim is inadequate.
- **HDR10+ / Dolby Vision HDMI dynamic signaling:** not implemented as a
  GTK/GDK display-link feature; a tone-map option or tag cannot provide it.

## Reproducible build and hardware qualification

On Debian 13 with the required toolchain and libmpv:

```sh
meson setup build -Dgtk=true -Dmpv=enabled -Dtests=true \
  -Dexperimental_embedded_gpu_next=false -Dexperimental_gtk_pq=false
meson compile -C build
meson test -C build --print-errorlogs
```

Then build against **matching, deliberately patched** libmpv headers and
runtime (unmerged `MPV_RENDER_PARAM_BACKEND` interface):

```sh
PKG_CONFIG_PATH=/path/to/patched/lib/pkgconfig \
meson setup build-pq -Dgtk=true -Dmpv=enabled -Dtests=true \
  -Dexperimental_embedded_gpu_next=true -Dexperimental_gtk_pq=true
meson compile -C build-pq
meson test -C build-pq --print-errorlogs
```

With an appropriate Wayland GNOME/HDR monitor setup, verify at least:
(a) one source replacement under a slow compositor, (b) repeated 4K resizing
and realization/disposal, (c) active driver memory budget, (d) readback
verification of the PQ transfer and luminance against a reference,
(e) external monitor HDR signaling, and (f) separate Profile 7 MEL/FEL
reference comparisons. Fail the release gate if those cannot be demonstrated.

**Status:** This is not a finished, certified Stage 7 media renderer. Unsupported
stable embedding APIs and hardware output-signaling requirements cannot be
completed by modifying the GTK wrapper alone. Do not enable the experimental
renderer in the default Majoris OS image without qualification.
