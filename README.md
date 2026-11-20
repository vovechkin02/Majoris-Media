# Majoris Media

**Version:** 0.7.0 (Stage 7 advanced SDR rendering policies and telemetry) · **API namespaces:** `MediaKit-1.0`,
`MediaKitGtk-1.0` · **Platform:** Majoris OS / Debian 13 · **License:** GPL-3.0-or-later

Majoris Media is a reusable audio/video playback foundation for Majoris applications.
It consists of a **headless GObject Core** and an **optional GTK4 presentation library**.
It uses **libmpv** for asynchronous playback, FFmpeg-backed demuxing/decoding through
libmpv, and a **GtkGLArea**-attached OpenGL renderer. Applications retain ownership of
windows, playlists, toolbars, persistent settings, and fullscreen policy.

> **Verification status:** This is source implementation, not a validated release.
> Stage 7 static checks passed, but Vala, Meson, libmpv and GTK4 development
> packages were unavailable in the authoring environment. Native compilation,
> runtime playback, GTK rendering, ICC processing and hardware output are
> **not verified**.
> Build and run the tests on Debian before integrating this into the ISO.

## Contents

- [Current implementation](#current-implementation)
- [Codec and output policy](#codec-and-output-policy)
- [Dependencies and building](#dependencies-and-building)
- [Quick start](#quick-start)
- [Public API](#public-api)
- [Architecture and source layout](#architecture-and-source-layout)
- [Compatibility, security and resources](#compatibility-security-and-resources)
- [Testing and qualification](#testing-and-qualification)
- [Contributing and documentation](#contributing-and-documentation)
- [License](#license)

## Current implementation

| Area | Stage 7 status |
| --- | --- |
| Local file and HTTP(S) source identity | Implemented; scheme validated before playback |
| Per-session native engine | libmpv adapter implemented; independent handles |
| Asynchronous opening | Complete only on actual libmpv `FILE_LOADED` or failure |
| Cancellation / replacing a source | Cancellable native task and request-generation gating |
| Play / pause / stop / seek | Native commands; times in signed 64-bit microseconds |
| Playback events | EOF, terminal errors, operation errors, pause, position, duration |
| GTK video | OpenGL rendering through `GtkGLArea` and libmpv render API |
| GTK transport | Play/pause, stop, seek, time, Video/Audio/Subtitles/Chapters and Output menus |
| GTK templates | All widget layout in `.ui` XML resources |
| Track/chapter discovery | Live `GListModel` snapshots from typed libmpv properties |
| Track/subtitle selection | Video, audio, subtitle ID, subtitle off and visibility toggles |
| Chapter navigation | Indexed chapters and actual current chapter observation |
| Buffering and seek state | Cache pause, percentage, seeking and engine events |
| Video decoder status | Observed `hwdec-current`, including software fallback |
| Source color metadata | Live `VideoColorInformation`: transfer, primaries, range, matrix, HDR flags, luminance and DV profile when available |
| Embedded video target | SDR BT.709/BT.1886 processing, configurable legacy-compatible tone mapping |
| Renderer quality | Opt-in bounded debanding, default balanced |
| Framebuffer telemetry | GL RGB bit depth and render dithering depth measured on active framebuffer; no HDR output inference |
| Embedded gpu-next | Unavailable in this adapter pending an official supported API |
| Display ICC | Optional caller-provided ICC blob through `mpv_render_context_set_parameter`; profile selection belongs to host |
| Native HDR policy | `PREFER_NATIVE` rejected until actual GTK/compositor HDR output exists; no false positive |
| Media probe | Standalone probe API reserved; still reports unavailable |
| Audio source and output metadata | Independent `AudioInformation` and `AudioOutputInformation` live snapshots |
| Multichannel PCM | `PcmChannelPolicy.SYSTEM_DEFAULT` (safe) or `PRESERVE_SOURCE` (source-preferred, device permitting) |
| Audio output devices | Enumerated libmpv device IDs and optional runtime switching in PCM mode |
| Compressed passthrough | Explicit endpoint and receiver-approved AC-3, E-AC-3, TrueHD, DTS, DTS-HD allowlist; default is PCM |
| Physical receiver validation | **Not implemented**; encoded output is an engine observation, not verified Atmos/DTS:X |
| Dolby Vision FEL / native HDR / Atmos / DTS:X rendering | Not qualified; output capabilities explicitly unverified |
| DVD/Blu-ray title navigation | Typed disc source, titles/editions, and selection implemented; real discs not qualified |
| DVD/Blu-ray menus | Conditional mpv 0.42+ `discnav` commands and GTK controls; hardware/disc testing pending |
| Standalone M2TS | Independent local transport stream path and synthetic sample |

`-Dmpv=enabled` is the default and **requires** libmpv and libepoxy development
packages; missing dependencies stop configuration rather than silently generating a
non-playing release. An intentionally non-playing build can use `-Dmpv=disabled`
for API development and headless testing.

## Stage 7 rendering

`PlaybackOptions.tone_mapping` controls one of four validated SDR algorithms:
`AUTO`, `BT2390`, `MOBIUS`, or `HABLE`; `video_quality` selects `BALANCED`
(default) or opt-in `HIGH_QUALITY` debanding. Policies are set before opening a
new source. `MediaView.rendering_information` and its change signal provide
GTK framebuffer RGB bit depths, the libmpv render-depth parameter, whether a
caller-supplied ICC profile was accepted, and a submitted-frame indication.
The telemetry is sampled only when needed, not on every decoded frame.

**This is not native HDR:** libmpv's embedded OpenGL path remains an SDR
pipeline. A 10-bit framebuffer does not establish HDR scanout. `gpu-next`,
Dolby Vision Profile 7 MEL/FEL, compositor HDR10+ signaling, and real native
HDR must be implemented and validated separately. See
[advanced rendering](docs/advanced-rendering.md) and
[Stage 7 verification](docs/verification-stage7.md).

## Codec and output policy

Decoding capability is supplied by the installed libmpv build and its FFmpeg
libraries. **No blanket format/codec or hardware-decoding guarantee is made.**
Stage 7 retains a PCM WAV smoke fixture plus a tiny generated MKV with two
PCM audio tracks, one MPEG-4 video track, subtitles and two chapters. This is
not a complete format qualification matrix. Source HDR signaling is not equivalent to native
HDR output; Atmos/DTS:X sources do not guarantee object-audio rendering or
encoded receiver passthrough. Read [formats](docs/formats.md).

## Dependencies and building

Required with Stage 7 default options:

- Meson >=1.4, Ninja, `valac`, C compiler, GLib/GIO >=2.76.
- `libmpv-dev` and `libepoxy-dev` for the native engine and GL resolver.
- GTK4 >=4.16 and GLib resource tooling when `-Dgtk=true` (default).
- GObject-introspection compiler to produce typelib artifacts; force
  `-Dintrospection=enabled` in Debian package builds.

Debian 13 development example:

```sh
sudo apt install meson ninja-build valac libglib2.0-dev libgtk-4-dev \
  libmpv-dev libepoxy-dev gobject-introspection
meson setup build -Dmpv=enabled -Dgtk=true -Dtests=true -Dexamples=true \
  -Dintrospection=enabled
meson compile -C build
meson test -C build --print-errorlogs
sudo meson install -C build
```

Headless Core with actual libmpv (no GTK developer dependencies):

```sh
meson setup build-headless -Dgtk=false -Dexamples=false -Dmpv=enabled
meson compile -C build-headless
meson test -C build-headless --print-errorlogs
```

Optional no-engine API development build:

```sh
meson setup build-nompv -Dmpv=disabled -Dgtk=false -Dexamples=false
meson compile -C build-nompv
meson test -C build-nompv --print-errorlogs
```

The build provides `libmajoris-media.so.0`, optional
`libmajoris-media-gtk4.so.0`, VAPIs, C headers, GIR/typelibs when the compiler
is present, and pkg-config files. Debian packaging files are in `debian/`.

## Quick start

This is usage *inside an async method* where a GTK window has already been
realized and `cancellable` is a caller-owned `GLib.Cancellable?`:

```vala
var session = new MediaKit.MediaSession ();
var view = new MediaKitGtk.MediaView ();
var controls = new MediaKitGtk.MediaControls ();
view.session = session;
controls.session = session;

try {
    var source = new MediaKit.MediaSource.for_path ("/home/user/Videos/movie.mkv");
    yield session.open_async (source, cancellable);
    session.play ();
} catch (Error error) {
    warning ("Unable to play media: %s", error.message);
}
```

Stage 3+ track selection after a successful open:

```vala
for (uint index = 0; index < session.tracks.get_n_items (); index++) {
    var track = (MediaKit.MediaTrack) session.tracks.get_item (index);
    if (track.kind == MediaKit.TrackKind.AUDIO && !track.selected) {
        session.select_audio_track (track.id);
        break;
    }
}

session.set_subtitles_visible (true);
```

`select_audio_track()` queues a request; inspect `tracks_changed` or the model
for the actual engine-selected track. Use `operation_failed` for asynchronously
rejected controls. Subtitle track selection and visibility are separate.

Stage 5 audio output and safe multichannel playback:

```vala
var options = new MediaKit.PlaybackOptions ();
options.audio_policy = MediaKit.AudioOutputPolicy.DECODE_PCM;
options.pcm_channel_policy = MediaKit.PcmChannelPolicy.PRESERVE_SOURCE;
var session = new MediaKit.MediaSession (options);
// After open_async() succeeds, inspect session.audio_devices and audio_output.
// PRESERVE_SOURCE does not guarantee the output hardware preserves that layout.
```

For encoded HDMI passthrough, select an exact ID actually returned by
`session.audio_devices` in an earlier PCM session, verify codec support using
receiver-specific documentation/configuration, and create a fresh session:

```vala
var options = new MediaKit.PlaybackOptions ();
options.audio_policy = MediaKit.AudioOutputPolicy.PREFER_PASSTHROUGH;
options.audio_device_id = selected_device_id;
options.passthrough_codecs = MediaKit.AudioPassthroughCodec.AC3 |
    MediaKit.AudioPassthroughCodec.EAC3 |
    MediaKit.AudioPassthroughCodec.TRUEHD;
var session = new MediaKit.MediaSession (options);
```

`selected_device_id` must be the actual identifier previously enumerated;
**do not** copy arbitrary display names or assume HDMI capabilities from its
name. `audio_output.transport == ENCODED_OBSERVED` indicates only that libmpv
reported an IEC 61937 stream. External receiver recognition, Atmos height/object
rendering and DTS:X are not validated by this API. Device selection does not
silently carry a codec allowlist to a different device.

Stage 4 source-color inspection after a successful open:

```vala
var color = session.video_color;
if (color.is_hdr) {
    message ("Source HDR format: %s", color.hdr_format.to_string ());
}
// This remains an SDR GTK target. Native HDR is not yet supported.
assert (session.color_output_target == MediaKit.ColorOutputTarget.SDR_BT709_BT1886);
```

The host may pass a monitor ICC profile as `GLib.Bytes` to
`view.set_display_icc_profile(profile)`. Do not load arbitrary network ICC
profiles; selection and monitor changes remain the host's responsibility. A
native-HDR-only playback policy returns `MediaError.UNSUPPORTED` before opening
because GtkGLArea output cannot yet verify HDR scanout. `AUTO` and
`TONE_MAP_SDR` select the conservative SDR path.

Run `build/examples/majoris-media-demo` under a graphical session for the
interactive Open Media file picker. Rendering works with one active GTK view
per `MediaSession` (libmpv supports only one render context per core).

## Public API

- `MediaKit.MediaSource` accepts local paths and file/HTTP(S) URIs.
- `MediaKit.MediaSession` owns open/close, play/pause/stop/seek, observable state,
  `position_us`, `duration_us`, `state_changed`, `position_changed`,
  `duration_changed` and `output_changed`. Its live read-only `tracks` and
  `chapters` models expose stream selection, chapter navigation and subtitles.
- `MediaKit.VideoColorInformation` reports source colorimetry and observed HDR
  metadata; neither it nor `color_output_target` guarantees native HDR scanout.
- `MediaKit.OpenGlOutput` is a GTK-independent GL presentation endpoint. Only
  create/render/release it with the host OpenGL context current.
- `MediaKit.MediaTrack` includes ID, kind, codec, language, title, selection and
  source flags; `MediaChapter` includes timestamp and title. `MediaProbe` still
  lacks a standalone inspection implementation; output policy remains advisory.
- `MediaKitGtk.MediaView` embeds the video GL renderer and accepts an optional
  `set_display_icc_profile(GLib.Bytes?)` provided by the embedding application.
  `MediaKitGtk.MediaControls`
  supplies optional transport, track, subtitle and chapter controls. See
  [API details](docs/api.md).

## Architecture and source layout

`src/core/` contains public GObject types and the private playback Strategy.
`native/playback/` contains a C GObject Adapter using libmpv plus the OpenGL
render API. `src/gtk/` contains neutral XML-templated GTK4 widgets. `tests/`
contains focused Core, GTK, and native-engine smoke tests. See
[architecture](docs/architecture.md) for lifetime and thread invariants.

## Compatibility, security and resources

- This is an **unstable pre-release** API with provisional SONAME 0. Do not
  treat `-1.0` GIR namespace identifiers as a frozen API version.
- The Core remains GTK-free. GTK frame rendering occurs only with a current
  GL context. Sources and engine instances do not share mutable global state.
- Arbitrary media is untrusted. libmpv/FFmpeg are native decoders operating in
  process, **not** sandboxed decoder workers in Stage 4. No security isolation
  against malicious codecs/containers is claimed.
- HTTP(S) URLs can initiate network traffic and access remote resources.
  Callers should impose their own trust policy and sandbox/process isolation.
- The engine currently uses `hwdec=auto-safe`; actual GPU interoperability,
  native HDR and encoded HDMI audio paths remain unverified. SDR color-target
  setup and libmpv tone-mapping wiring are implemented but not visually qualified.
- libmpv rendering requires a valid active GL context. A session exposes one
  renderer at a time; do not share its renderer across unrelated GL contexts.
- Source supersession and cancellation are generation-checked. Source switching
  creates a fresh engine and releases the old renderer first. UI mutations
  must happen on the owning GLib main context.

## Testing and qualification

The native smoke test opens a short PCM WAV; a separate representative generated
MKV exercises live track/chapter discovery and track/visibility controls.
Source validation, cancellation and GTK session binding are covered separately.
See [testing](docs/TESTING.md) and the precise
[Stage 7 verification report](docs/verification-stage7.md). No benchmarks are
claimed; hardware decoding, 4K, HDR and receiver passthrough need target
hardware qualification.

## Contributing and documentation

Follow [CONTRIBUTING.md](CONTRIBUTING.md) and the bundled
[Majoris Cross-Project Engineering Standards v1.8](docs/engineering-standards-v1.8.md).
Declarations require meaningful Valadoc/gtk-doc. Observe ownership, cancellation,
GoF participant boundaries, en-US identifiers, XML UI and focused tests.

## License

GPL-3.0-or-later; see [LICENSE](LICENSE). The repository does not vendor VLC,
libmpv or FFmpeg source code. Their linked library licenses and dependencies
must be evaluated for binary redistribution and Debian packaging.

## Stage 6 — DVD, Blu-ray and standalone M2TS

Stage 6 added explicit DVD/Blu-ray source construction, isolated optical-disc
device configuration, native disc-title/edition inventory and selection, and
conditional interactive menu support on mpv 0.42+. `.m2ts` can be opened as a
normal local file independently of a Blu-ray disc. `MediaKitGtk` optionally
shows Titles and Disc Menu controls, with focus-aware keyboard navigation.

Disc media playback depends on the installed libmpv/libbluray/DVD stack and
source accessibility. No protected-disc decryption is bundled. See
`docs/disc-playback.md` and `docs/verification-stage6.md` for the important
limitations and release checks.
