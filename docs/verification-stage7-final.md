# Stage 7.2 advanced renderer — verification report

**Version:** 0.7.2

**Scope:** Advanced Wayland `gpu-next` process control, transport diagnostics,
source-aware dynamic tone mapping, and optional GTK4 controls. This is a
source-level implementation, not a verified native HDR display release.

## Source changes

- Added `GpuNextIpc` with private Unix socket, JSON-GLib serialization,
  request-ID matching, event skipping, bounded replies and async watchdog.
- `GpuNextWindow.open_async` now waits for a responsive IPC connection, not
  just successful spawn. It handles cancellation, close, duplicate launch,
  startup failure, process exit and temporary-directory cleanup.
- Added asynchronous `set_paused_async`, `seek_async`, `query_status_async` and
  immutable `GpuNextPlaybackStatus`. A source's primaries/transfer are reported
  separately from unverified native HDR monitor output.
- Added `GpuNextToneMapping` policies for mpv `auto`, `st2094-40`, `st2094-10`.
- Added XML-backed `MediaKitGtk.GpuNextControls` with simple transport controls.
- Added an original no-rendering Python mpv IPC process double to test
  control-plane semantics and unsolicited notifications without hardware.
- Updated Meson, Debian source packaging and the architecture/API references.

## Checks

| Gate | Status | Evidence |
| --- | --- | --- |
| Static layering/source/XML | PASSED | `python3 tools/check_structure.py` |
| Declaration documentation | PASSED | `python3 tools/check_source_docs.py` |
| Python smoke fixture syntax | PASSED | `python3 -m py_compile tests/support/mpv` |
| Python fixture IPC protocol smoke | PASSED | Exercise with isolated Unix socket |
| ZIP CRC, metadata and permissions | PASSED | Archive inspection |
| Vala/Meson build | NOT RUN | Development packages unavailable here |
| C/GObject/Vala integration suite | NOT RUN | Development toolchain unavailable here |
| GTK4 interactive rendering | NOT RUN | Requires Wayland/GPU environment |
| Native HDR compositor/monitor scanout | UNVERIFIED | Requires real display qualification |
| Embedded gpu-next and full DV P7 FEL within GTK | NOT IMPLEMENTED | No stable upstream Linux libmpv embedding API |
| Full HDR10+ / Dolby Vision HDMI metadata signaling | NOT IMPLEMENTED | Per-scene HDR10 target hints are not proprietary dynamic metadata |

## Debian qualification commands

```sh
sudo apt install meson ninja-build valac libglib2.0-dev libjson-glib-dev \
  libgtk-4-dev libmpv-dev libepoxy-dev gobject-introspection
meson setup build -Dmpv=enabled -Dgtk=true -Dtests=true \
  -Dintrospection=enabled
meson compile -C build
meson test -C build --print-errorlogs
```

Test the advanced IPC fixture independently of actual hardware; then install
mpv 0.42+ with FFmpeg/libplacebo versions supporting DV P7 FEL and qualify
HDR10, HDR10+, HLG, Dolby Vision 5/8 and Profile 7 MEL/FEL against actual
GNOME/Mutter output, frame references, and an HDR monitor. Log whether output
was true HDR scanout or SDR tone mapping. Keep these as different results.
