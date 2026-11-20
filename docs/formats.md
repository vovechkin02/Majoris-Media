# Playback format targets and qualification — Stage 4

Stage 4 delegates format selection and decoding to the installed libmpv/FFmpeg
build. A codec being present upstream does **not** establish hardware decoder,
GTK render, display HDR, object audio or receiver passthrough support.

| Family | Target | Qualification needed before advertising support |
| --- | --- | --- |
| PCM audio | WAV (included smoke fixture), FLAC, ALAC | Real output and lossless samples |
| Compressed audio | MP3, AAC, Opus, Vorbis, WMA | Decoder discovery + representative playback |
| Video | H.264, HEVC, AV1, VP8/VP9, MPEG-1/2/4, VC-1, ProRes, FFV1 | Decode + frame presentation, profile-specific |
| Containers | MKV, MP4/MOV, AVI, TS/MTS/M2TS, WebM, Ogg | Seekability, stream duration and track behavior |
| HDR video | HDR10, HLG, HDR10+, Dolby Vision profiles, Profile 7 MEL/FEL | Metadata processing + native display/tonemap evidence |
| Advanced audio | AC-3, E-AC-3, TrueHD, DTS, DTS-HD and DTS:X, Dolby Atmos | Decode and/or verified encoded receiver passthrough |
| Disc/navigation | DVD, Blu-ray, UHD Blu-ray, disc ISO, standalone M2TS | Navigation and disc access separately qualified |
| Subtitles | SRT, ASS, SSA, PGS and other text/bitmap streams | Selection, timing, layout and drawing |

libmpv/OpenGL embedding does not automatically enable mpv `gpu-next` features,
including complete Dolby Vision Profile 7 enhancement-layer processing.
Native HDR presentation requires compositor, DRM and monitor confirmation.
Encoded Atmos/DTS:X passthrough requires actual receiver support and correctly
configured PipeWire/ALSA. These remain **unverified**.

Network sources are limited by `MediaSource` to `file`, `http` and `https`.
M3U8/DASH and other protocol expansion will be addressed with a controlled
security policy. Commercial disc decryption is not supplied by this library.

## Stage 4 color/HDR implementation and limits

Stage 4 reads `video-params` and available DV profile properties from libmpv,
exposing source colorimetry in `VideoColorInformation`. HDR10 (PQ), HLG and
HDR10+ scene-max values are classified only when observed; Dolby Vision
requires metadata/profiles from the engine. Support depends on libmpv version
and actual decoded stream metadata, not on file-extension recognition.

The embedded renderer explicitly targets **BT.709 / BT.1886 SDR**, with
libmpv handling input gamut conversion and HDR-to-SDR tone mapping. The host
may provide an ICC display profile using the libmpv render API. This is an
implemented **output policy**, not a validated claim of accurate rendered
pixels or native HDR. Actual HDR swapchains, HDR10+ dynamic output metadata,
Dolby Vision monitor signaling, GPU-next and Profile 7 FEL processing remain
unavailable/unverified in this GTK OpenGL path. `PREFER_NATIVE` is rejected
rather than silently returning an SDR image under a native HDR promise.

The included `hdr10-reference.mp4` is an original one-frame 64×64 HEVC Main10
source with BT.2020 primaries and PQ transfer tags. `ffprobe` validates the
encoded stream metadata; this does not validate a monitor output or HDR10+
metadata support.

## Stage 3 representative test evidence

The generated `multi-stream.mkv` fixture contains MPEG-4 video, two PCM audio
tracks with English and French language tags, a SubRip subtitle stream and two
chapters. It exercises list discovery, stream IDs, selection and chapter control
when run with a real libmpv build. The PCM WAV smoke fixture remains. Neither
fixture establishes HDR, hardware decoding, encoded passthrough or broad codec
support.
