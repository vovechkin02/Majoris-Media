# Stage 7 verification record — 2026-11-20

## Scope

This revision adds a bounded legacy-OpenGL-compatible SDR tone-mapping policy,
an optional debanding policy, actual GL framebuffer channel-depth sampling,
accurate `MPV_RENDER_PARAM_DEPTH` selection for dithering, and a per-view
`VideoRenderingInformation` GObject snapshot with change notifications.
The cached renderer observations do not allocate or parse GVariants on every
video frame. The legacy constructors remain supported, and the Core library
remains independent of GTK4.

A narrow native smoke test constructs a session with BT.2390 and high-quality
processing and opens the supplied WAV fixture. It does not claim to test HDR.

## Checks completed in this environment

| Check | Status | Scope |
| --- | --- | --- |
| `python3 tools/check_structure.py` | PASS | Meson inventories, XML, layering, whitespace |
| `python3 tools/check_source_docs.py` | PASS | Handwritten declaration documentation |
| `python3 -m compileall tools` | PASS | Python static syntax |
| Source test registration and media fixtures | PASS | Test files present, FFprobe sample metadata |
| ZIP integrity and file mode | PASS | `debian/rules` executable, archive CRC verified |
| Native C build | NOT RUN | `glib-2.0` and other development headers absent |
| Vala/Meson build | NOT RUN | `valac` and Meson absent |
| Unit/integration runtime | NOT RUN | Native build prerequisites absent |
| GTK live FBO bit-depth telemetry | NOT RUN | Requires working GTK/GL/libmpv machine |
| HDR tone-map image accuracy | NOT RUN | Requires calibrated display and visual comparison |
| Native HDR, HDR10+ output signaling, DV Profile 7 FEL | NOT IMPLEMENTED | Needs supported rendering and Wayland/monitor path |

## Release qualification on Majoris Debian 13

```sh
sudo apt install meson ninja-build valac libglib2.0-dev libgtk-4-dev \
  libmpv-dev libepoxy-dev gobject-introspection
meson setup build -Dmpv=enabled -Dgtk=true -Dtests=true \
  -Dintrospection=enabled
meson compile -C build
meson test -C build --print-errorlogs
```

Verify both normal `AUTO` and explicit `BT2390`/high-quality output, and
inspect runtime FBO precision for each GPU driver under GNOME/Wayland.
Compare BT.709 grayscale, HDR10 reference tone mapping, file switching,
ICC-profile changes, GLArea resize and teardown under GL debugging.

**Critical limitation:** This stage does **not** fully deliver the originally
proposed native HDR / gpu-next / Dolby Vision FEL features. Upstream libmpv's
supported render API and the GTK/compositor path are still missing the required
verified integration. See `advanced-rendering.md` for the remaining tasks.
