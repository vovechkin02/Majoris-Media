# Media support targets (not Stage 1 capabilities)

**Everything in the target columns below is unimplemented in Stage 1.**
No media source has been decoded, timed, rendered, output, probed or played.
Future reports should be based on actual discovered codecs and output support.

| Family | Future target | Qualification requirement |
| --- | --- | --- |
| Video codecs | H.264, HEVC, AV1, VP8/VP9, MPEG-1/2/4, VC-1, ProRes, DNx, FFV1 | Working decoder path for given bit depth/profile |
| Containers | MP4/MOV, MKV, WebM, AVI, TS/MTS/M2TS, MPEG-PS, Ogg, ASF | Reliable demux, seek and track discovery |
| Audio | MP3, AAC, Opus, Vorbis, FLAC, ALAC, PCM, WMA, DSD and compatible FFmpeg formats | Real decode/output, not extension matching |
| Dolby/DTS | AC-3, E-AC-3, TrueHD, DTS, DTS-HD MA/HR | Correct PCM rendering or validated encoded passthrough |
| Object audio | Atmos over E-AC-3/TrueHD, DTS:X over DTS-HD | Source metadata + *real* receiver capability confirmation |
| HDR | HDR10, HLG, HDR10+, Dolby Vision including Profile 7 MEL/FEL | Metadata interpretation, renderer correctness and separate output check |
| Files and discs | Local, network, Blu-ray, UHD Blu-ray, DVD, bare M2TS | Disc navigation and encryption/access evaluated separately |
| Subtitles | Text, ASS/SSA, embedded and PGS | Accurate timestamps, font scaling, picture overlays |

The target baseline is libmpv/FFmpeg, with libplacebo/native rendering analysis
and VLC as an architectural reference. Embedded libmpv output is not assumed to
have the same advanced `gpu-next` features as a standalone mpv process. Both
HDR10+ and Dolby Vision require careful dynamic metadata and frame/output
validation. Commercial disc encryption/keys and proprietary object-audio
software rendering are separate licensing/technical constraints.
