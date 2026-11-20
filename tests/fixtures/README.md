# Original test media fixtures

`short-tone.wav` is the Stage 2 deterministic PCM audio smoke fixture.

`multi-stream.mkv` is a new Stage 3 deterministic sample constructed with FFmpeg
from generated color-bar/test patterns, 440 Hz and 660 Hz synthetic sine waves,
and two original English subtitle lines. It contains:

- One 96×64 MPEG-4 video stream at 6 frames per second, three seconds long.
- Two mono 16 kHz PCM audio streams (language tags `eng` and `fra`).
- One SubRip subtitle stream.
- Two source chapters: `Beginning` and `Second chapter`.

`hdr10-reference.mp4` is an original one-frame, 64×64 HEVC Main10 reference
with BT.2020 primaries and SMPTE ST 2084 (PQ) transfer tags. It is useful for
probing source metadata but does **not** validate tone mapping or monitor HDR.

The fixture is checked into the repository so tests require no runtime FFmpeg
CLI. It contains no third-party creative media. Use `ffprobe` to inspect stream
metadata when adding new assertions. These two short samples are **not** a codec,
HDR, audio passthrough or performance benchmark suite.
