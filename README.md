# Majoris Media

**Version:** 0.1.0 (Stage 1 architecture baseline) · **API namespaces:** `MediaKit-1.0`,
`MediaKitGtk-1.0` · **Platform target:** Majoris OS / Debian 13 · **License:** GPL-3.0-or-later

Majoris Media is the proposed shared multimedia foundation for Majoris applications.
It is split into a **headless GObject Core** (`MediaKit`) and an **optional reusable
GTK4 presentation library** (`MediaKitGtk`). The public `MediaSession`/`MediaSource`
contracts intentionally do not expose libmpv, FFmpeg, GPU APIs, or GTK objects.

> **Stage 1 scope:** This source archive implements the library/API scaffolding,
> Meson targets, native integration seam, XML GTK templates, and focused contract
> tests. **It does not decode, play, probe, render, or stream media yet.** Playback
> requests fail explicitly with `MediaError.ENGINE_UNAVAILABLE`; the GTK transport
> action is disabled. Do not interpret declared formats or metadata enums as support
> for specific media files or native HDR/Atmos/DTS:X output.

## Contents

- [Features and current status](#features-and-current-status)
- [Supported media and format strategy](#supported-media-and-format-strategy)
- [Requirements and dependencies](#requirements-and-dependencies)
- [Building and installing](#building-and-installing)
- [Quick start](#quick-start)
- [Public API](#public-api)
- [Architecture and source layout](#architecture-and-source-layout)
- [Compatibility, security and resources](#compatibility-security-and-resources)
- [Testing and release qualification](#testing-and-release-qualification)
- [Documentation and contribution](#documentation-and-contribution)
- [License](#license)

## Features and current status

| Area | Current result |
| --- | --- |
| Media source identification | Local path and file/HTTP/HTTPS URI identity; no media I/O |
| Playback sessions | Construction, lifecycle state and error contracts; no engine |
| Source probing | Public asynchronous contract; returns engine-unavailable |
| Stream/chapters descriptors | GObject API types; not populated by a decoder |
| Output negotiation | Explicit unknown/unverified statuses; no active probing |
| GTK4 widget | XML-templated `MediaView` that observes session state; no video surface |
| GTK4 controls | Optional `MediaControls` widget, safely disabled |
| Backend | A deliberate unavailable adapter, not a fake libmpv implementation |
| VLC integration | No VLC source code is copied or linked into the library |
| Disc, HDR, Atmos, DTS:X | Deferred to separately verified future stages |

## Supported media and format strategy

**No input media is currently playable.** The architecture anticipates locally
stored audio/video and compatible HTTP(S) media resources, then future disc
sources, using FFmpeg-backed playback through an engine adapter. See
[`docs/formats.md`](docs/formats.md) for codec/container/HDR/audio *targets*,
not a misleading list of working codecs.

Format inspection, decode availability, display HDR presentation, encoded HDMI
passthrough, and disc decryption are separate capabilities and must be reported
independently. A Dolby Vision or Atmos flag in source metadata cannot prove
that a monitor or receiver reproduces the intended mastering/output format.

## Requirements and dependencies

- Debian 13 (Trixie), a C compiler and Vala compiler (`valac`).
- Meson **1.4 or newer** and Ninja; GLib/GIO development files **2.76 or newer**.
- Optional GTK4 development files **4.16 or newer** for `MediaKitGtk`.
- Optional `gi-compile-repository` or `g-ir-compiler` for installed introspection typelibs.
- `glib-compile-resources` (from GLib development tooling) when building GTK.
- No libmpv or FFmpeg build dependency in this deliberately non-playing Stage 1.

## Building and installing

Full build (core + GTK + example + focused tests):

```sh
meson setup build -Dgtk=true -Dexamples=true -Dtests=true
meson compile -C build
meson test -C build --print-errorlogs
sudo meson install -C build
```

**Headless core**, without GTK development packages or GTK test requirements:

```sh
meson setup build-core -Dgtk=false -Dexamples=false -Dtests=true
meson compile -C build-core
meson test -C build-core --print-errorlogs
```

To require typelibs instead of silently skipping an unavailable compiler:

```sh
meson setup build-gir -Dintrospection=enabled -Dgtk=true
meson compile -C build-gir
```

The install provides versioned shared libraries, Vala VAPIs and `.deps` files,
public C headers, pkg-config files, and (when enabled) GIR files and typelibs.
Package build scaffolding lives in `debian/`.

## Quick start

This example shows the Stage 1 API contract. The `open_async` call throws
`MediaError.ENGINE_UNAVAILABLE` until Stage 2 implements a real backend.

```vala
var session = new MediaKit.MediaSession ();
var view = new MediaKitGtk.MediaView ();
view.session = session;

try {
    var source = new MediaKit.MediaSource.for_path ("/home/user/Videos/example.mkv");
    yield session.open_async (source, cancellable);
    session.play ();
} catch (Error error) {
    warning ("Media opening is unavailable: %s", error.message);
}
```

The sample assumes an enclosing Vala `async` method and a `cancellable`
variable. For an executable, use `meson compile -C build majoris-media-demo`
and then the resulting `build/examples/majoris-media-demo` under a GTK display.

## Public API

- `MediaKit.MediaSource`: local path or file/HTTP(S) URI identity.
- `MediaKit.MediaSession`: independent session, `open_async`, `play`, `pause`,
  `stop`, microsecond `seek`, `close`, `state_changed` and error reporting.
- `MediaKit.MediaProbe`: asynchronous `inspect_async` contract.
- `MediaKit.MediaDescription`, `MediaTrack`, `MediaChapter`: metadata structure.
- `MediaKit.VideoInformation`, `AudioInformation`: source metadata types.
- `MediaKit.MediaCapabilities`: conservative runtime/output capability snapshot.
- `MediaKit.PlaybackOptions`: opt-in audio/HDR/seek policies without claiming support.
- `MediaKitGtk.MediaView` (`MediaKitView` GType): reusable neutral GTK media surface.
- `MediaKitGtk.MediaControls` (`MediaKitControls` GType): optional GTK transport control group.

See [`docs/api.md`](docs/api.md) for state transitions and ownership contracts.

## Architecture and source layout

`src/core/` contains the GTK-independent public GObject API and internal
playback interface. `native/playback/` houses the small C backend boundary;
its Stage 1 adapter always reports unavailable. `src/gtk/` contains the optional
GTK widget library and `data/ui/` contains GTK XML templates. An example
consumer lives in `examples/`; focused checks live in `tests/`.

See [`docs/architecture.md`](docs/architecture.md) for dependency direction,
GoF pattern decisions, lifecycle invariants and the Stage 2 handoff.

## Compatibility, security and resources

- The namespace and soname are pre-release contracts (`0.1.0`, soname `0`).
  Before a stable release, review changes to GTypes, GIR/VAPI, constructor
  arguments, signals, property semantics, and unit conventions.
- The core must never link GTK, call GTK or require a running display server.
- Construction does not read a source. No network requests, disc I/O, decoder
  processes, untrusted-media parsers, or hidden shell commands exist in Stage 1.
- `MediaSource` admits only local paths and file/HTTP(S) URIs. Stage 2 must
  separately implement input validation, media size/time budgets, security
  isolation decisions and network access controls.
- Session state is owned by its main-context caller. Late open callbacks are
  generation-checked; GTK signal listeners disconnect on rebinding/disposal.
- HDR and encoded audio capabilities remain explicitly unverified rather than
  being inferred from format-name enums or available library dependencies.

## Testing and release qualification

Focus is deliberately narrow: source validation, empty/unavailable state,
async error/cancellation, and widget/session binding. No media benchmarks are
claimed for a repository with no decoder, presenter or audio output. See
[`docs/TESTING.md`](docs/TESTING.md) for exact verification commands and
known validation limitations.

## Documentation and contribution

Architecture, API contracts, current format targets and engineering standards
are under [`docs/`](docs/); working conventions live in
[`CONTRIBUTING.md`](CONTRIBUTING.md). All new code must follow the bundled
Majoris Cross-Project Engineering Standards v1.8, including documentation of
private declarations, C/Vala ownership, GObject conventions, GoF intent, XML
GTK UI, and focused test granularity.

## License

GPL-3.0-or-later. See [`LICENSE`](LICENSE). The Stage 1 source archive contains
original scaffolding; it does not vendor or copy any VLC/FFmpeg code.
