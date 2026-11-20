# Stage 7.4 — Experimental GTK BT.2100/PQ output verification

**Version:** 0.7.4
**Date:** 2026-11-21
**Status:** Source implementation. Native compilation, patched-libmpv rendering and
monitor HDR verification have **not** been performed.

## What this pass implements

1. A separate `MediaKitGtk.HdrMediaView` GTK4 widget, compiled only with the
   explicit Meson flags `experimental_embedded_gpu_next=true` and
   `experimental_gtk_pq=true`. The widget does not change the default
   `MediaKitGtk.MediaView` rendering behavior or its ABI.
2. A private GTK/GL bridge that uses an RGBA16F framebuffer as the target for
   the patched libmpv OpenGL `gpu-next` render API. Each completed frame is
   transferred without CPU readback into an immutable `GdkGLTextureBuilder`
   texture labeled `GDK_COLOR_STATE_REC2100_PQ`. The bridge uses the matching
   floating-point GDK memory format and holds a GL context ref until each
   submitted texture is released by GTK.
3. A new `HdrOutputPolicy.EXPERIMENTAL_PQ_TEXTURE`, distinct from the still-
   rejected `PREFER_NATIVE`. When selected for a newly opened session, libmpv
   is configured with BT.2020 primaries and a PQ transfer curve rather than
   the normal BT.709/BT.1886 SDR target. The target selection is frozen for
   the active source. This protects the standard `MediaView` from receiving
   mislabeled PQ pixels.
4. GPU resource cleanup, context-bound renderer attachment, frame-change-
   driven redraw, immutable frame lifetime, bounded maximum render size, and
   fail-closed behavior if float framebuffer construction is unavailable.
5. Focused Core source-policy and optional GTK widget contracts, and updated
   architecture, API, and packaging documentation.

## What remains unverified or unsupported

- Whether the unmerged upstream libmpv `gpu-next` GL API actually compiles and
  renders correctly against the selected patched runtime.
- Whether GTK and Mutter communicate the HDR color state to the active
  Wayland output and monitor in the actual Majoris OS runtime.
- Native HDR monitor scanout, correct displayed luminance, Wide Color Gamut,
  mastering metadata and EOTF; color-tagging a GL texture is not proof.
- Complete Dolby Vision Profile 7 FEL reconstruction accuracy. This depends
  on a compatible mpv/FFmpeg/libplacebo chain and comparison media.
- Dynamic HDR10+ (ST 2094-40) or proprietary Dolby Vision metadata signaling
  over the display link. `GdkColorState` PQ tagging is not a dynamic HDR output
  protocol.
- Full production performance at 4K60 and GPU-memory peaks. This experimental
  bridge allocates an immutable texture per *new frame*, not per widget redraw;
  investigate a fence-aware texture pool once actual benchmarks justify it.
- Native source compilation, since this environment lacks Meson, Vala, GLib,
  GTK4, libmpv and libepoxy development packages.

## Build gates on Debian 13

Build the normal (unchanged) stable SDR path first:

```sh
meson setup build -Dmpv=enabled -Dgtk=true -Dtests=true \
  -Dexperimental_embedded_gpu_next=false -Dexperimental_gtk_pq=false
meson compile -C build
meson test -C build --print-errorlogs
```

Then use an isolated, intentionally patched libmpv with consistent headers and
runtime libraries:

```sh
PKG_CONFIG_PATH=/path/to/patched/lib/pkgconfig \
meson setup build-hdr -Dmpv=enabled -Dgtk=true -Dtests=true \
  -Dexperimental_embedded_gpu_next=true -Dexperimental_gtk_pq=true
meson compile -C build-hdr
meson test -C build-hdr --print-errorlogs
```

The opt-in build must reject absent patch headers. The runtime must reject
unsupported floating-point GL targets without falling back to SDR while
claiming PQ. Exercise session replacement, pause/seek, reparenting, monitor
moves, widget realization and disposal, and loss of the Wayland HDR output.

Example application integration (illustrative API):

```vala
var options = new MediaKit.PlaybackOptions ();
options.hdr_policy = MediaKit.HdrOutputPolicy.EXPERIMENTAL_PQ_TEXTURE;
var session = new MediaKit.MediaSession (options);
var view = new MediaKitGtk.HdrMediaView ();
view.session = session;
// Realize the view in a GTK window before starting playback.
yield session.open_async (new MediaKit.MediaSource.for_path ("/movie.mkv"));
```

`view.pq_texture_submitted` reports only a color-tagged frame submitted to
GTK, and `view.presentation` remains `UNVERIFIED`. It does not advertise
`NATIVE_HDR` solely from GL precision or the source's HDR metadata.

## Checks performed in this authoring environment

- Static source/XML/Meson-inventory/layering checks: **pass**.
- Source declaration-documentation checks: **pass**.
- Source package ZIP integrity and executable bits: verify at archive creation.
- Native compilation and runtime tests: **not run** (development toolchain missing).
- GPU/HDR monitor and Dolby Vision FEL tests: **not run** (hardware/patched
  runtime unavailable).

**Release gate:** Do not ship the experimental widget in default Debian/ISO
packages or market it as complete Stage 7 native HDR until the above
qualification results have been recorded against real hardware and a stable
supported upstream renderer API.
