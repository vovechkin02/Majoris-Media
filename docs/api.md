# Public API and operation contracts — Stage 2 (0.2.0)

## Stability and types

Public namespaces remain `MediaKit-1.0` and `MediaKitGtk-1.0`; SONAME 0 is
pre-release. Version 0.2.0 is not an ABI-stable production release.

| Type | Role | Behavior in Stage 2 |
| --- | --- | --- |
| `MediaSource` | Local path or file/HTTP(S) URI | Construction does not touch disk/network |
| `MediaSession` | Per-source playback Facade | Async load, play/pause, stop, seek, EOF, error and time events |
| `OpenGlOutput` | GL renderer endpoint | One active renderer per engine, GL-context-affine |
| `MediaCapabilities` | Verified/unknown output state | Engine availability from build; HDR/audio output unverified |
| `MediaProbe` | Future async media inspection | Still returns `ENGINE_UNAVAILABLE` |
| `MediaDescription`, `MediaTrack`, `MediaChapter` | Metadata models | Reserved; not yet populated by decoder |
| `PlaybackOptions` | Audio/HDR/seek policy | Stored only; unsupported advanced choices not silently enabled |
| `MediaKitGtk.MediaView` | Video display | GTK GLArea + libmpv embedded OpenGL API |
| `MediaKitGtk.MediaControls` | Optional controls | Play, pause, stop, position seek |

## State and events

- An untouched session is `EMPTY`. `open_async` enters `OPENING`, and only the
  native `MPV_EVENT_FILE_LOADED` completion permits transition to `READY`.
- An open command error or load failure raises a GLib error and enters `ERROR`.
  The error is available in `last_error` until `close()` or the next open.
- `play`, `pause`, `stop`, and `seek` request native commands that return after
  *acceptance*, not physical audio output or video scanout. Session states
  reflect accepted commands with later native pause/EOF/failure observations.
- `ENDED` indicates an actual natural EOF, not an explicit stop. `stop`
  retains the loaded source by pausing and returning the playhead to zero.
- `position_us`/`duration_us` are signed int64 microseconds. Duration is zero
  when unknown. `seek(position_us)` rejects negative values. Duration updates
  come from libmpv observations; a source may remain nonseekable.
- `output_changed` signals that renderers for the previous engine must be
  detached and new renderers can be created. The UI must not keep an older
  engine's GL context after it receives this event.
- Before opening a video, realize the `MediaView` so its render context exists.
  If no renderer is present, a headless audio source may still play.

## Ownership, cancellation and execution contexts

- `MediaSession` owns the internal playback backend and one `Cancellable` for
  its current load. Superseding an operation cancels the prior engine task.
- The native engine uses a `GTask` completed by actual libmpv events or
  cancellation. No blocking `mpv_wait_event()` runs on the GTK main thread;
  libmpv wakeups are marshaled as idle sources to the owning GLib context.
- Engine and renderer callbacks are coalesced to avoid unbounded idle dispatch.
- The engine's `mpv_handle` is not publicly exposed. `OpenGlOutput` owns a
  native renderer, which retains its engine until renderer release.
- `MediaView` calls `OpenGlOutput.detach()` with its GL context current before
  source replacement, widget unrealize or widget disposal. Native GL rendering
  happens on the thread/context that created the render context.
- Only one renderer is permitted per native engine, per libmpv API design.
- Widget signal IDs are disconnected before their sessions are replaced.
- Call all `MediaSession` mutators from its owning GLib context. Cross-thread
  public remote control is not supported in Stage 2.

## Errors and capability claims

Missing libmpv in a deliberately disabled build produces
`MediaError.ENGINE_UNAVAILABLE` for playback. Native initialization, load,
OpenGL and command errors are propagated rather than replaced by success.

`MediaCapabilities.playback_engine=AVAILABLE` means an mpv-backed build is
present, not that a particular output device/codec has been demonstrated.
`native_hdr`, `encoded_audio` and `hdr_presentation` remain UNVERIFIED; Dolby
Vision/Atmos/DTS:X or hardware GPU acceleration must not be claimed based on
source tags or library availability alone.
