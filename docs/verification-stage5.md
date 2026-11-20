# Stage 5 verification record — 2026-11-20

## Scope

Source changes cover the headless `MediaKit` audio models, `PlaybackOptions`
format allowlist and PCM layout policy, the libmpv C adapter, and GTK's
output-device selector. Default decoded-PCM behavior is retained from Stage 4.
The new public contracts do **not** assert that Atmos/DTS:X object decoding or
HDMI receiver acceptance was actually tested.

## Checks actually executed

| Check | Result | Evidence |
| --- | --- | --- |
| `python3 tools/check_structure.py` | PASS | Core/GTK dependency boundary, Meson source inventory, XML templates, source whitespace |
| `python3 tools/check_source_docs.py` | PASS | 473 of 473 detected Vala/C declarations documented |
| `ffprobe` 5.1 FLAC reference | PASS | `flac`, 48 kHz, six channels, `5.1` |
| `ffprobe` E-AC-3 reference | PASS | `eac3`, 48 kHz, six channels, `5.1(side)` |
| Native Meson/valac compilation | NOT RUN | `meson`, `valac`, GLib/GTK4/libmpv development headers are absent |
| Unit/integration tests compiled and executed | NOT RUN | Depends on above toolchain and libmpv runtime |
| PipeWire/ALSA 5.1/7.1 channel preservation | NOT RUN | Requires corresponding output hardware and software stack |
| AC-3, E-AC-3, TrueHD, DTS, DTS-HD bitstream passthrough | NOT RUN | Requires configured HDMI endpoint, receiver, licensed sample files and measured observations |
| Dolby Atmos/DTS:X external object rendering | NOT RUN | Requires supported receiver and independently verified object-audio media |

## Required Debian 13 release commands

```sh
sudo apt install meson ninja-build valac libglib2.0-dev libgtk-4-dev \
  libmpv-dev libepoxy-dev gobject-introspection
meson setup build -Dmpv=enabled -Dgtk=true -Dtests=true \
  -Dintrospection=enabled
meson compile -C build
meson test -C build --print-errorlogs
```

Also compile `-Dgtk=false -Dexamples=false` to verify the Core's GTK-free
build. Verify the built shared-library symbol inventory and installed GIR/VAPI
loading and run the demo with an actual GL context and audio endpoint. When
validating HDMI, compare `audio-out-params` with the receiver's own mode
indication; do not classify `audio-spdif` configuration as actual delivery.

The above source checks are not a substitute for native compilation or target
hardware qualification. Stage 5 is **source-implemented, not release-verified**.
