# Stage 4 verification record — 2026-11-20

## Scope

The Stage 3 source archive is the base. Stage 4 implements source-color metadata
observation, a typed HDR classification contract, an explicit embedded-OpenGL
SDR output target, bounded host-provided ICC profile support, and conservative
native-HDR-policy rejection. It **does not** implement or claim native monitor
HDR, full HDR10+ output signaling or Dolby Vision Profile 7 FEL reconstruction.

## Executed checks

- **PASS:** Repository source inventories, XML template parsing, Core/GTK layering,
  UTF-8, whitespace and LF formatting (`tools/check_structure.py`).
- **PASS:** Declaration-level documentation coverage checked using
  `tools/check_source_docs.py`.
- **PASS:** Reference HDR10 HEVC Main10 fixture inspected by `ffprobe`: `hevc`,
  `yuv420p10le`, `bt2020nc`, `smpte2084` and `bt2020` stream tags.
- **PASS:** Archive file inventory and CRC verification after ZIP creation.
- **CHECKED:** The updated native C layer uses documented libmpv
  `MPV_RENDER_PARAM_ICC_PROFILE` and `MPV_RENDER_PARAM_DEPTH` interfaces.
  This is source/API review, **not** native linking or runtime testing.

## Not run / remaining risks

- **NOT RUN:** Meson setup, Vala generation, native compilation and link.
- **NOT RUN:** GObject GIR/VAPI/typelib compilation or Debian binary packaging.
- **NOT RUN:** Unit and integration binaries, GTK playback and ICC application.
- **NOT RUN:** HDR10/HDR10+/HLG/Dolby Vision rendering comparisons or colorimeter
  measurement, SDR gamma/ICC correctness on actual GNOME monitors.
- **NOT RUN:** Dolby Vision Profile 7 MEL/FEL processing; native 10-bit/HDR
  compositor scanout (intentionally not exposed by the current renderer).

The authoring container lacks Meson, valac, GLib/GIO, GTK4, libmpv and epoxy
headers/pkg-config metadata. `apt-get update` was attempted and failed to fetch
package indexes because DNS for deb.debian.org was unavailable. No compiler
pass is claimed; static validation does not rule out source-level errors.

## Debian 13 release qualification

```sh
sudo apt install meson ninja-build valac libglib2.0-dev libgtk-4-dev \
  libmpv-dev libepoxy-dev gobject-introspection
meson setup build -Dmpv=enabled -Dgtk=true -Dtests=true \
  -Dintrospection=enabled
meson compile -C build
meson test -C build --print-errorlogs
```

Qualify a correctly configured GNOME/Wayland and X11 display with the original
HDR10 reference file and real HDR10, HLG and HDR10+ dynamic-scene samples.
Check output using reference images/colorimetry tools, not only video source
tags. Apply a trusted monitor ICC profile and verify its effect; test malformed
profiles, profile clearing, monitor changes, renderer teardown and source
replacement. Verify native-HDR preference returns UNSUPPORTED without changing
an already playing session. Keep native HDR and Profile 7 FEL explicitly
unverified until an advanced renderer and real display/output qualification exist.
