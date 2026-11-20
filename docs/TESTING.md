# Testing and release qualification — Stage 7

## Focused tests

| Test | Suite | Purpose |
| --- | --- | --- |
| `media-source-documentation` | unit | Verify Valadoc/gtk-doc summaries on handwritten definitions |
| `media-source-structure` | unit | Meson source inventories, XML templates, layering, UTF-8 and whitespace |
| `media-core-contract` | unit | Source/lifecycle rules plus Stage 4 SDR, HDR10, HLG, HDR10+, DV classification and unsupported native HDR |
| `media-engine-playback` | integration | Tiny generated WAV, actual `FILE_LOADED`, play, pause, seek, stop, restart |
| `media-engine-metadata` | integration | Original multistream MKV: track inventory/selection, chapters, subtitle visibility, model reset |
| `media-gtk-contract` | integration | GTK templates and independent session assignment |

The native audio fixture is `tests/fixtures/short-tone.wav`: 500 ms of 16 kHz
mono 16-bit PCM. The second original fixture, `multi-stream.mkv`, is 3 seconds
with one MPEG-4 video, two PCM audio tracks, one SRT track and two chapters.
Both fixtures are committed and deterministic; test execution needs no FFmpeg
CLI installed.
The tiny HEVC reference fixture also permits later native HDR10 detection
qualification. These are **metadata** tests, not monitor-color correctness,
HDR10+ dynamic scene-processing, Dolby Vision FEL, Atmos or 4K benchmarks.

## Commands

```sh
meson setup build -Dmpv=enabled -Dgtk=true -Dtests=true -Dexamples=true
meson compile -C build
meson test -C build --print-errorlogs

python3 tools/check_source_docs.py
python3 tools/check_structure.py
```

The GTK tests use the environment's GDK backend. To run them on Debian without
a display server, use `xvfb-run -a dbus-run-session -- meson test -C build --print-errorlogs`.
Run the demo on Wayland/X11 with a real GL renderer to validate video, seek,
close/reopen, source switching and GLArea unrealize/realize. Observe frame
latency and memory during repeated playback cycles before raising performance
claims. Test the headless core build separately with `-Dgtk=false`.

## Release gates

1. `meson setup`, compilation, link, VAPI/GIR generation and typelib compile.
2. Core unit and engine smoke tests with a real libmpv installation.
3. GTK widget integration on a functional GDK backend.
4. Repeated open/cancel/reopen, close/dispose, audio-only and video source tests.
5. Real device checks: Intel/AMD/NVIDIA GL, Wayland/X11, sample MP4/MKV, no audio
   sink, decoder fallback, window resize and GL context replacement.
6. Debian binary package installation, library loading and actual standalone
   consumer compilation.

The source authoring environment had no valac, meson, GLib/GTK4 or libmpv
headers and no package download access. Therefore Stage 5 native compilation,
GIR generation and runtime tests are **NOT RUN**, not passed. See
[verification-stage5.md](verification-stage5.md).

## Stage 5 audio qualification

- Unit contract tests classify unknown, decoded PCM and engine-observed IEC 61937
  output separately; TrueHD source metadata never asserts Dolby Atmos.
- Passthrough policy tests reject the system-default device with a requested
  codec set **before** a media source is opened. Empty sessions reject device
  selection and expose no fictitious hardware capabilities.
- Integration fixtures `surround-5.1.flac` and `surround-eac3.eac3` contain
  exactly six channels at 48 kHz. Engine source-track recognition is tested when
  libmpv is compiled in; tests do not require a physical surround receiver.
- Real-hardware qualification is still required for PipeWire and ALSA:
  sample-rate negotiation, 2.0/5.1/7.1 PCM, PCM fallback, device unplugging,
  HDMI ELD formats, AC-3/E-AC-3/TrueHD/DTS/DTS-HD passthrough, sync, audio
  delay and receiver front-panel codec identification. Atmos/DTS:X object
  presentation requires appropriate separately licensed test media and an AVR
  capable of showing the actual decoded/object mode.
- Never classify a source track codec or `audio-spdif` configuration string
  as a proven passthrough or spatial-audio qualification result.
- Native compile/run **not performed** in the authoring container (valac,
  Meson, GLib/GTK4/libmpv development headers unavailable). See the precise
  check record in `verification-stage5.md`.

## Stage 6 qualification

Run the new `media-engine-standalone-m2ts` integration test on a libmpv-enabled
build. Validate source constructors and error behavior through the Core unit
test. For optical-disc qualification, separately check DVD, Blu-ray folder,
Blu-ray ISO, title/playlist selection, chapter navigation and real disc menus
on both stock Debian and an mpv 0.42+ build. Use only test media that can
legally be accessed. For real disc drive testing, also verify cancellation,
missing discs, source replacement and eject/reinsert behavior.

## Stage 7 renderer qualification

- `media-core-contract` includes policy and framebuffer-metadata cases; no
  hard-coded bit depth is inferred from HEVC Main10 source metadata.
- `media-engine-video-policy` initializes a real libmpv instance with explicit
  BT.2390 tone mapping and high-quality debanding. It opens the existing WAV
  fixture and validates option acceptance, **not** HDR video output.
- `media-gtk-contract` verifies a never-realized GTK widget does not claim a
  rendered frame, even when a playback session is bound.
- Manually verify `VideoRenderingInformation` against the framebuffer and
  compare SDR/HDR-to-SDR imagery on calibrated equipment. Monitor native HDR,
  HDR10+, Dolby Vision FEL, and `gpu-next` are **not** implemented here.
- See [advanced-rendering.md](advanced-rendering.md) and
  [verification-stage7.md](verification-stage7.md) before ISO inclusion.

## Stage 7.1 optional gpu-next qualification

Core unit cases `/media/core/stage7-gpu-next-candidate` and
`/media/core/stage7-gpu-next-arguments` verify the version gate, Wayland
candidate status, GPU-next fixed argv, source-path argument terminator, network
opt-in, unsupported disc inputs, and empty process lifecycle. These tests do
not need a real Wayland compositor or mpv process, but must be compiled with
Vala to run. The example offers a manually invoked external gpu-next window;
run its separate hardware qualification against native HDR, HDR10+
scene-hints, and legal Dolby Vision 7 MEL/FEL references. See
[verification-stage7-completion.md](verification-stage7-completion.md).

## Stage 7.2 separate-renderer controller

`media-gpu-next-ipc-controller` uses a local Python `mpv` process double rather
than a GPU. It checks the preflight-to-ready handshake, private Unix-domain
socket permissions, unsolicited JSON event filtering, pause, precise seek,
source color/VO status, and terminal cleanup. This is a **control-plane** test,
not a decoder, tone-mapping, FEL reconstruction, or Wayland HDR validation.
The default Core/GTK smoke cases remain unchanged; do not add duplicate tests
for every media codec simply to inflate coverage.

The standalone Wayland display qualification gate is separate: check the
actual installed mpv/FFmpeg/libplacebo versions, compositor protocol and
HDR-enabled monitor, run reference SDR/HDR10/HLG/HDR10+/DV Profile 5/8/7
content, compare screenshots and external HDR signaling, and record whether
HDR output was directly signaled or tone-mapped. Native HDR success cannot be
inferred from the `GpuNextPlaybackStatus` source transfer field.

## Stage 7.4 experimental PQ texture path

- Core tests verify that a PQ request is refused when the patched libmpv
  feature is absent and that no native HDR capability is inferred.
- The opt-in `media-gtk-hdr-contract` test verifies unloaded widget state
  and session attachment without requiring a GPU.
- A real patched build must prove RGBA16F framebuffer completeness, context
  lifetime, immutable texture ownership, and correct GDK BT.2100/PQ tagging.
  Do not count these checks as passed based on this repository's static tests.
- Hardware colorimetry, Wayland HDR mode, compositor conversion, 4K frame
  performance, HDR10+ metadata and Dolby Vision Profile 7 FEL reproduction
  remain independently required before any product support claim.

## Stage 7.5 framebuffer and HDR metadata corrections

The Core classification test now verifies that HDR10 scene peak metadata
alone does **not** imply HDR10+; only a synthetic explicit confirmed dynamic
metadata signal may select the HDR10+ enum. The same suite checks that patched
embedded gpu-next is not marked `AVAILABLE` solely from compile-time support.

The opt-in patched runtime must test both float-frame rendering success and
failure: RGB16F, an eight-bit FBO, missing GLsync, resize, source replacement,
reparenting, and GTK renderer teardown. In particular the raw `render_pq`
operation must fail on an SDR-configured engine, and the ordinary `render`
operation must reject a PQ-configured engine. These tests require working GL
and patched libmpv, not this source-only authoring environment. Do not count
source-code inspection as proof that GTK, Mutter and the monitor support HDR.

### Stage 7.6 native resource safety

`media-hdr-frame-budget` is a single independent C11/pthreads unit test covering
per-view allocation bounds, recovery, independent lifetime references and
concurrent reservations. It does not claim to exercise GL, GTK or libmpv.
On development machines it can also run without Meson:

```sh
gcc -std=gnu11 -Wall -Wextra -Werror -O2 -pthread \
  -I native/gtk native/gtk/hdr-frame-budget.c \
  tests/unit/hdr-frame-budget.c -o /tmp/majoris-hdr-budget
/tmp/majoris-hdr-budget
```

Native GTK color-state correctness and monitored HDR output still require the
patched build plus hardware/Wayland validation; see
`verification-stage7-0.7.6.md`.

### Stage 7.7 texture-format and GL state qualification

Run the two GTK-independent native C11 tests on any development machine:

```sh
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -I native/gtk \
  native/gtk/hdr-frame-budget.c tests/unit/hdr-frame-budget.c -o /tmp/hdr-frame-budget
/tmp/hdr-frame-budget
cc -std=c11 -Wall -Wextra -Werror -O2 -I native/gtk \
  native/gtk/hdr-frame-format.c tests/unit/hdr-frame-format.c -o /tmp/hdr-frame-format
/tmp/hdr-frame-format
```

These tests deliberately exercise only pure C storage and lifetime contracts.
The GTK resource bridge and GL state saving must additionally be compiled and
exercised with GTK4, patched libmpv and a real OpenGL display. Do not mark that
hardware test as passing based only on a static or C11 test.
