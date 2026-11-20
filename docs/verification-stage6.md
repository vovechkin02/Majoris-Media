# Stage 6 verification record — 2026-11-20

## Implemented source scope

Stage 6 adds a distinct headless disc source contract, a typed optical-disc title
model, per-session disc metadata snapshots, a native libmpv disc device option
adapter, title selection, and conditional menu navigation with GTK titles and
navigation popovers. `MediaView` routes focus-aware navigation keys. A separate
standalone M2TS path uses the existing file/media demuxer, not a Blu-ray
playlist service. Public Stage 1–5 APIs remain in place.

## Checks actually executed

| Check | Result | Notes |
| --- | --- | --- |
| `python3 tools/check_structure.py` | PASS | Meson inventories, XML UI, separation, source text |
| `python3 tools/check_source_docs.py` | PASS | 532 of 532 detected Vala/C declarations documented |
| XML parser | PASS | GTK templates and resource XML |
| `ffprobe tests/fixtures/standalone-reference.m2ts` | PASS | 256 × 192-byte packets, MPEG-2 video and MP2 audio |
| ZIP archive integrity | PASS | Verified after packing |
| C native compilation | NOT RUN | GLib development headers missing |
| Vala/Meson compilation | NOT RUN | valac and Meson not installed |
| Libmpv file playback and M2TS integration | NOT RUN | No installed libmpv development/runtime environment |
| DVD VIDEO_TS/DVD ISO title navigation | NOT RUN | No known-good disc media or drive |
| Blu-ray BDMV/ISO/MPLS/PGS validation | NOT RUN | No disc-media test infrastructure |
| UHD Blu-ray menu and seamless branching | NOT RUN | No validated mpv 0.42+ UHD test system |
| Encrypted DVD/Blu-ray/UHD disc access | NOT SUPPORTED AS A CLAIM | No decryption components or keys included |

## Target Debian release commands

```sh
sudo apt install meson ninja-build valac libglib2.0-dev libgtk-4-dev \
  libmpv-dev libepoxy-dev gobject-introspection
meson setup build -Dmpv=enabled -Dgtk=true -Dtests=true \
  -Dintrospection=enabled
meson compile -C build
meson test -C build --print-errorlogs
```

Repeat with `-Dgtk=false -Dexamples=false` to test the headless Core; run the
embedded GTK view and hardware optical-disc matrix separately. For menu support,
verify against an mpv **0.42+** runtime with libbluray and BD-J dependencies.
Stock Debian 13 may ship an earlier libmpv without interactive navigation.
Do not claim Blu-ray UHD/HDR/Atmos/DTS:X compatibility merely from a successful
transport-stream demux or source metadata read.

This stage is **source implemented but not native-build verified**.
