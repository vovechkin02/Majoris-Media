# Playback format targets and qualification — Stage 2

Stage 2 delegates format selection and decoding to the installed libmpv/FFmpeg
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
