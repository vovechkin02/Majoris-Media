# Testing and release qualification — Stage 3

## Focused tests

| Test | Suite | Purpose |
| --- | --- | --- |
| `media-source-documentation` | unit | Verify Valadoc/gtk-doc summaries on handwritten definitions |
| `media-source-structure` | unit | Meson source inventories, XML templates, layering, UTF-8 and whitespace |
| `media-core-contract` | unit | Valid/rejected URIs, initial states, missing file, pre-canceled load |
| `media-engine-playback` | integration | Tiny generated WAV, actual `FILE_LOADED`, play, pause, seek, stop, restart |
| `media-engine-metadata` | integration | Original multistream MKV: track inventory/selection, chapters, subtitle visibility, model reset |
| `media-gtk-contract` | integration | GTK templates and independent session assignment |

The native audio fixture is `tests/fixtures/short-tone.wav`: 500 ms of 16 kHz
mono 16-bit PCM. The second original fixture, `multi-stream.mkv`, is 3 seconds
with one MPEG-4 video, two PCM audio tracks, one SRT track and two chapters.
Both fixtures are committed and deterministic; test execution needs no FFmpeg
CLI installed.
No HDR, Atmos or large decoder benchmark tests are justified at this stage.

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
headers and no package download access. Therefore Stage 3 native compilation,
GIR generation and runtime tests are **NOT RUN**, not passed. See
[verification-stage3.md](verification-stage3.md).
