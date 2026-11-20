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

Run the GTK test with a working headless backend or an Xvfb/virtual compositor.
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
