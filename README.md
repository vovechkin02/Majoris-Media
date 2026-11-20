# Majoris Media

**Version:** 0.2.0 (Stage 2 playback prototype) · **API namespaces:** `MediaKit-1.0`,
`MediaKitGtk-1.0` · **Platform:** Majoris OS / Debian 13 · **License:** GPL-3.0-or-later

Majoris Media is a reusable audio/video playback foundation for Majoris applications.
It consists of a **headless GObject Core** and an **optional GTK4 presentation library**.
It uses **libmpv** for asynchronous playback, FFmpeg-backed demuxing/decoding through
libmpv, and a **GtkGLArea**-attached OpenGL renderer. Applications retain ownership of
windows, playlists, toolbars, persistent settings, and fullscreen policy.

> **Verification status:** This is source implementation, not a validated release.
> Stage 2 static checks passed, but a native compiler, Vala, mpv and GTK4 SDKs were
> unavailable in the authoring environment. Build, libmpv loading, GPU rendering,
> and hardware outputs MUST be verified on a Debian target before ISO integration.

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

| Area | Stage 2 status |
| --- | --- |
| Local file and HTTP(S) source identity | Implemented; scheme validated before playback |
| Per-session native engine | libmpv adapter implemented; independent handles |
| Asynchronous opening | Complete only on actual libmpv `FILE_LOADED` or failure |
| Cancellation / replacing a source | Cancellable native task and request-generation gating |
| Play / pause / stop / seek | Native commands; times in signed 64-bit microseconds |
| Playback events | End-of-file, error, pause, duration and position |
| GTK video | OpenGL rendering through `GtkGLArea` and libmpv render API |
| GTK transport | Play/pause, stop, seek slider and time labels |
| GTK templates | All widget layout in `.ui` XML resources |
| Track/chapter discovery | API structures only; enumeration postponed to Stage 3 |
| Media probe | API reserved; still reports unavailable |
| HDR / Atmos / DTS:X | Not qualified; output capabilities explicitly unverified |
| Blu-ray navigation | Not implemented; dedicated later stage |

`-Dmpv=enabled` is the default and **requires** libmpv and libepoxy development
packages; missing dependencies stop configuration rather than silently generating a
non-playing release. An intentionally non-playing build can use `-Dmpv=disabled`
for API development and headless testing.

## Codec and output policy

Decoding capability is supplied by the installed libmpv build and its FFmpeg
libraries. **No blanket format/codec or hardware-decoding guarantee is made.**
Stage 2 has a small PCM WAV fixture for a focused smoke test, not a complete
format qualification matrix. Source HDR signaling is not equivalent to native
HDR output; Atmos/DTS:X sources do not guarantee object-audio rendering or
encoded receiver passthrough. Read [formats](docs/formats.md).

## Dependencies and building

Required with Stage 2 default options:

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

Run `build/examples/majoris-media-demo` under a graphical session for the
interactive Open Media file picker. Rendering works with one active GTK view
per `MediaSession` (libmpv supports only one render context per core).

## Public API

- `MediaKit.MediaSource` accepts local paths and file/HTTP(S) URIs.
- `MediaKit.MediaSession` owns open/close, play/pause/stop/seek, observable state,
  `position_us`, `duration_us`, `state_changed`, `position_changed`,
  `duration_changed` and `output_changed`.
- `MediaKit.OpenGlOutput` is a GTK-independent GL presentation endpoint. Only
  create/render/release it with the host OpenGL context current.
- `MediaKit.MediaProbe`, metadata/track/chapter objects and playback policies
  preserve the Stage 1 API shapes; advanced probing is not implemented.
- `MediaKitGtk.MediaView` embeds the video GL renderer; `MediaKitGtk.MediaControls`
  supplies optional neutral controls. See [API details](docs/api.md).

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
  process, **not** sandboxed decoder workers in Stage 2. No security isolation
  against malicious codecs/containers is claimed.
- HTTP(S) URLs can initiate network traffic and access remote resources.
  Callers should impose their own trust policy and sandbox/process isolation.
- The engine currently uses `hwdec=auto-safe`; actual GPU interoperability,
  native HDR/tonemapping and encoded HDMI audio paths remain unverified.
- libmpv rendering requires a valid active GL context. A session exposes one
  renderer at a time; do not share its renderer across unrelated GL contexts.
- Source supersession and cancellation are generation-checked. Source switching
  creates a fresh engine and releases the old renderer first. UI mutations
  must happen on the owning GLib main context.

## Testing and qualification

The fixture-based native smoke test opens a short PCM WAV and exercises playback
controls. Source validation, cancellation and GTK session binding are tested
separately. See [testing](docs/TESTING.md) and the precise
[Stage 2 verification report](docs/verification-stage2.md). No benchmarks are
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
