# Architecture — Stage 1

## Scope and invariants

This phase establishes API names and ownership boundaries only. No decoder,
demuxer, renderer, audio mixer, disc reader, stream client or codec probing is
integrated. An unavailable operation MUST fail rather than return a plausible
metadata object, claim a native HDR path, or emit `PLAYING`.

The architecture follows the split proven by Majoris Image 2.0.1: Core is
GTK-independent, and GTK presentation consumes Core rather than the inverse.
The similarity is the component boundary, not an assumption that video can be
rendered using ImageKit's still-image buffer model.

```text
              Media Player / Files / other Majoris apps
                            |       |
                 MediaKitGtk |       | MediaKit
                      |      |       |
                 GTK widgets --------> Core APIs
                                      |
                            PlaybackBackend (internal)
                                      |
                          Native engine adapter (C)
                                      |
                          [Stage 2: libmpv bridge]
                                      |
                FFmpeg / rendering / output via engine
```

### Dependency rules

1. `MediaKit` links only GLib/GIO and its own native C shim in Stage 1.
2. `MediaKitGtk` links `MediaKit` plus GTK4. Its resource templates are bundled
   into the GTK library, not installed in a separate application directory.
3. Consumer applications own GTK windows, toolbars, playlists, settings and
   their other application-specific UI. The media widget owns no top-level
   application instance or window.
4. Native adapter decisions and library-specific error codes stay private.
5. ImageKit will remain responsible for artwork and still-image processing
   when Media Player integration is added; MediaKit will own moving media.

## Contracts and lifecycle

`MediaSource` wraps a GIO file. Path construction accepts a nonempty local path;
URI construction accepts only `file:`, `http:`, or `https:`. Neither operation
opens or validates an actual media file in Stage 1.

Each `MediaSession` owns one `PlaybackBackend` instance and exposes an enum
state, latest error, selected source, policy options, capability snapshot,
and `state_changed` signal. The initial backend is `UnavailableBackend`.
A real backend will replace that internal implementation, not the public API.
The native C functions in `native/playback/engine-adapter.[ch]` are a deliberate
seam and currently expose *only* backend unavailability.

- `EMPTY`: initial or after `close()`; source and error are null.
- `OPENING`: a live `open_async` request has begun.
- `READY`: a backend actually finished opening a source. Not reachable Stage 1.
- `PLAYING`, `PAUSED`, `STOPPED`, `ENDED`: reserved for real backend transitions.
- `ERROR`: a non-cancellation open failure. Error and requested source remain
  available until replaced or closed.
- A request canceled before opening does not modify session state. A canceled
  current opening resets to `EMPTY`. Superseded completion must not mutate a
  newer generation or republish a stale source.
- `play`, `pause`, `stop`, `seek` propagate backend errors without changing
  the state. Seeking uses signed 64-bit **microseconds**; negatives fail first.
- No open call reports READY until an actual backend confirms readiness.

`MediaProbe` has its own asynchronous API but is not tied to GUI objects.
It explicitly reports that the probe engine is absent, rather than constructing
fabricated `MediaDescription` objects.

`MediaCapabilities` deliberately distinguishes `UNKNOWN` and `UNVERIFIED` from
`AVAILABLE`, `UNAVAILABLE` and verified HDR presentation; metadata flags do not
imply device/output capabilities. The first delivered snapshot establishes
`playback_engine=UNAVAILABLE`, while leaving monitor HDR and encoded audio
output *unverified*.

`MediaView` and `MediaControls` subscribe to session state only while bound.
Each keeps a handler ID and disconnects on replacement and GObject disposal.
The XML template's `render_host` is a reserved presentation slot, not a fake
GtkGLArea that would prematurely constrain Stage 2.

All callbacks for GTK and session state are expected on the caller's owning
GLib main context. Thread-safe remote control and worker dispatch are
**not** promised by Stage 1.

## Design patterns (GoF intent)

| Design decision | Role | Why it exists |
| --- | --- | --- |
| `MediaSession` | Facade | Single API over lifecycle, source and future engine operations; not a God Object |
| `PlaybackBackend` | Strategy boundary | Playback implementations can vary without changing session API; no per-frame virtual calls |
| `UnavailableBackend` | Null-unavailable implementation, not Null Object | Explicit errors, no silently successful no-ops |
| `native/playback/engine-adapter.c` | C integration seam | Adapts future native engine interfaces, error/ownership; presently a stub, not an active Adapter instance |
| `state_changed` | GObject Observer idiom | GTK consumers can observe independently without custom event bus |

The GTK view is composed with a Core session. There is no Singleton, second
status bus, broad service locator, forced Abstract Factory or pattern hierarchy
for every media codec. Actual GoF participant contracts will be updated when a
real playback engine is introduced.

## Stage 2 integration boundary

Stage 2 is expected to add a functioning `libmpv`-backed implementation. Work
must establish the precise native event context, ownership of mpv handles and
render contexts, thread/hardware restrictions, error-code mapping, async
cancel/shutdown, GPU context loss and output-device negotiation.

**Do not** assume that existing embedded libmpv OpenGL rendering supports
all of `gpu-next`, Dolby Vision Profile 7 enhancement-layer processing, native
Wayland HDR scanout or encoded Atmos/DTS:X passthrough. Those remain separate
capabilities to verify with real hardware and reference media, and may require
an alternate rendering/output solution behind the existing boundary.

This phase intentionally introduces no `mpv` build dependency and copies no
VLC sources. VLC's demuxing, disc and audio-output implementations remain
architectural references subject to their own licensing and integration tests.
