# Public API and operation contracts — Stage 4 (0.4.0)

## Stability and types

Public namespaces remain `MediaKit-1.0` and `MediaKitGtk-1.0`; SONAME 0 is
pre-release. Version 0.4.0 is not an ABI-stable production release.

| Type | Role | Behavior in Stage 4 |
| --- | --- | --- |
| `MediaSource` | Local path or file/HTTP(S) URI | Construction does not touch disk/network |
| `MediaSession` | Per-source playback Facade | Async load, transport, track/chapter control, seek, EOF, errors and buffering |
| `OpenGlOutput` | GL renderer endpoint | One active renderer per engine, GL-context-affine |
| `MediaCapabilities` | Verified/unknown output state | Engine availability from build; native HDR/audio output unverified |
| `VideoColorInformation` | Typed source-only color/HDR descriptor | mpv `video-params` tokens, luminance and dynamic scene metadata if exposed |
| `MediaProbe` | Future async media inspection | Still returns `ENGINE_UNAVAILABLE` |
| `MediaDescription`, `MediaTrack`, `MediaChapter` | Metadata models | Live per-session tracks/chapters (standalone probe still reserved) |
| `PlaybackOptions` | Audio/HDR/seek policy | Stored only; unsupported advanced choices not silently enabled |
| `MediaKitGtk.MediaView` | Video display | GTK GLArea + libmpv embedded OpenGL API, optional caller-provided ICC blob |
| `MediaKitGtk.MediaControls` | Optional controls | Play, pause, stop, seek, video/audio/subtitle selection and chapters |

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
- Live `tracks` and `chapters` are read-only GListModel interfaces whose
  underlying contents are replaced on source/selection metadata updates.
  Consumers can use the `tracks_changed` and `chapters_changed` signals. Each
  MediaTrack reports the mpv ID, kind, codec, language, source title, selected,
  default, forced, and external flags. `selected_track_id(kind)` returns the
  actually selected ID or null. Selection commands **queue** a libmpv request;
  the next observed metadata event determines what is selected.
- `select_audio_track`, `select_video_track`, `select_subtitle_track`,
  `select_track`, `set_subtitles_visible`, and `select_chapter` reject invalid
  state and unknown track/chapter references. Null track ID disables that
  category (including subtitles). Visibility is independent of subtitle ID.
- `current_chapter_index` is -1 while unknown. Chapter indexes are zero-based,
  and `select_chapter` uses libmpv's chapter property (not an approximate seek).
- `is_buffering`, `buffering_percent` (-1 if unknown), and `is_seeking` are
  independent of the user-facing `PlaybackState`: cache starvation does not
  mean a user intentionally paused playback. Observers use `buffering_changed`
  and `seeking_changed`. Buffering percentage represents mpv's cache fill state,
  not downloaded-file completion.
- `active_video_decoder` is `""` until observed, `"no"` for software, or the
  active hardware decoder identifier reported by mpv. The
  `hardware_decoding_active` Boolean reflects this **observed** value, not the
  requested `hwdec=auto-safe` policy. No device support is inferred.
- `operation_failed` reports an asynchronously rejected selection/seek/pause
  command while preserving playback state. Terminal engine failure continues
  to transition to `ERROR` and set `last_error`.
- `output_changed` signals that renderers for the previous engine must be
  detached and new renderers can be created. The UI must not keep an older
  engine's GL context after it receives this event.
- Before opening a video, realize the `MediaView` so its render context exists.
  If no renderer is present, a headless audio source may still play.

## Stage 4 color and HDR contract

- `MediaSession.video_color` starts UNKNOWN and resets when a source is
  replaced/closed. `video_color_changed` fires only for changed values. The
  descriptor records source `primaries`, `transfer`, `matrix`, `color_levels`,
  `max_cll_nits`, `max_fall_nits`, mastering luminance, HDR10+ scene peak and
  Dolby Vision profile when libmpv actually exposes them.
- HDR10 is recognized from PQ transfer; HDR10+ requires *observed* dynamic
  scene metadata. HLG requires HLG transfer. Dolby Vision requires an observed
  DV profile or Dolby Vision matrix; no brand detection from filename/codec.
  Absent metadata remains UNKNOWN, not SDR by assumption.
- `color_output_target` is `SDR_BT709_BT1886`, expressing the requested mpv
  target only, not a proven signal from the compositor or monitor.
  `MediaCapabilities.native_hdr` and `hdr_presentation` are UNVERIFIED.
- `AUTO` and `TONE_MAP_SDR` use the same conservative SDR target. Setting
  `options.hdr_policy=PREFER_NATIVE` before `open_async` rejects with
  `MediaError.UNSUPPORTED` without replacing or opening any source. Changes to
  mutable options take effect on the next open, not mid-stream.
- `MediaKitGtk.MediaView.set_display_icc_profile(GLib.Bytes?)` applies a
  host-provided ICC profile while the GTK GL context is current, or stores it
  for the next renderer. Null clears it. The native adapter requires a sane
  ICC header and bounds the blob to 4 MiB. MediaKit does not discover
  monitor ICC profiles or open untrusted ICC file paths itself.
- Rendering delegates gamut conversion and SDR tone mapping to libmpv. These
  options require actual frame and monitor colorimetric qualification before
  asserting output accuracy. `gpu-next`, full Dolby Vision MEL/FEL, native
  HDR10/HDR10+ dynamic signaling, monitor EOTF and 10-bit presentation are not
  enabled by this embedded OpenGL stage.

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
  public remote control is not supported in Stage 4.

## Errors and capability claims

Missing libmpv in a deliberately disabled build produces
`MediaError.ENGINE_UNAVAILABLE` for playback. Native initialization, load,
OpenGL and command errors are propagated rather than replaced by success.

`MediaCapabilities.playback_engine=AVAILABLE` means an mpv-backed build is
present, not that a particular output device/codec has been demonstrated.
`native_hdr`, `encoded_audio` and `hdr_presentation` remain UNVERIFIED; Dolby
Vision/Atmos/DTS:X or hardware GPU acceleration must not be claimed based on
source tags or library availability alone.
