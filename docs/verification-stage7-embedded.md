# Stage 7.3 implementation and verification

**Version:** 0.7.3
**Date:** 2026-11-21
**Status:** Source-level implementation; native compilation and display
qualification not performed in this environment.

## Implemented changes

1. Added an **explicitly disabled by default** Meson option
   `experimental_embedded_gpu_next`. If enabled, configuration fails unless
   libmpv is present and its development header exports the nonstandard
   `MPV_RENDER_PARAM_BACKEND` identifier. It must link against the same patched
   libmpv runtime. No numeric ABI values are invented.
2. Added `mediakit_engine_create_renderer_gpu_next()` in the existing native C
   adapter. A second endpoint uses the draft's `"gpu-next"` backend request
   while continuing to render to the caller-owned GTK GL framebuffer. Original
   `mediakit_engine_create_renderer()` remains unchanged for standard builds.
3. Added `MediaSession.supports_experimental_gpu_next_embedding()` and
   `create_experimental_gpu_next_output()` to Core, plus a strict opt-in
   `MediaView.experimental_gpu_next` GTK property. Switching detaches the old
   render context on the GL thread before creating the new one.
4. Renderer telemetry identifies the experimental backend and deliberately
   refrains from labeling its post-processing result as native HDR or verified
   SDR. The existing legacy SDR telemetry is preserved.
5. Added post-processing `video-out-params` output primaries and transfer to
   `GpuNextPlaybackStatus` with a new named constructor to preserve the
   existing constructor's ABI. These properties are not physical display
   measurements. Extended the fake-mpv IPC test and focused API tests.

## Checks performed

- Repository structure/XML static check: **passed**.
- Declaration documentation static check: **passed**.
- Python fake-mpv wire-protocol smoke test: **passed**, including source color,
  post-process color, pause and seek (stub only, not a native renderer).
- ZIP integrity, source inventory and Debian executable permissions: verified
  during archive creation.
- Native Vala/Meson/libmpv build: **not run** (toolchain/development packages
  unavailable here).
- Patched libmpv build: **not run** (the upstream PR remains unmerged).
- Native HDR10/HDR10+/HLG, DV Profile 7 MEL/FEL, HDMI signals, GPU performance:
  **not run** (requires supported GPU, Wayland HDR compositor, display test
  equipment, licensed sample assets and a matching engine build).

## Practical compile qualification (Debian 13)

Run a normal release build first using packaged dependencies:

```sh
meson setup build -Dmpv=enabled -Dgtk=true -Dtests=true \
  -Dexperimental_embedded_gpu_next=false
meson compile -C build
meson test -C build --print-errorlogs
```

For a **non-shipping experimental build only**, install a deliberately patched
libmpv, with matching header and runtime library, in an isolated prefix, then:

```sh
PKG_CONFIG_PATH=/path/to/patched/lib/pkgconfig \
meson setup build-experimental -Dmpv=enabled -Dgtk=true \
  -Dexperimental_embedded_gpu_next=true
meson compile -C build-experimental
meson test -C build-experimental --print-errorlogs
```

A missing enum must fail Meson configuration. Use `MediaView.experimental_gpu_next`
explicitly; a failure must present an error, not substitute the legacy path.
With a reference HDR monitor, log the actual compositor/Wayland color state,
output EOTF, swapchain format, peak luminance, and frame measurements. Validate
sample-by-sample Dolby Vision FEL reconstruction with independent comparison.
`VideoRenderingInformation` / `GpuNextPlaybackStatus` are **diagnostic evidence**,
not a substitute for those measurements.

## Release blockers

**Stable embedded gpu-next, true GTK native-HDR presentation, proprietary
Dolby Vision output signaling, HDMI HDR10+ dynamic metadata, and FEL accuracy
remain unimplemented or unverified.** Do not mark Stage 7 fully closed or ship
claims of those capabilities based only on these changes.
