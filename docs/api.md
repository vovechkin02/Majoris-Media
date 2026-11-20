# Public API and operation contracts — Stage 7.5 (0.7.5)

## Stability and types

Public namespaces remain `MediaKit-1.0` and `MediaKitGtk-1.0`; SONAME 0 is
pre-release. Version 0.7.2 is not an ABI-stable production release.

| Type | Role | Behavior in Stage 5 |
| --- | --- | --- |
| `MediaSource` | Local path or file/HTTP(S) URI | Construction does not touch disk/network |
| `MediaSession` | Per-source playback Facade | Async load, transport, track/chapter control, seek, EOF, errors and buffering |
| `OpenGlOutput` | GL renderer endpoint | One active renderer per engine, GL-context-affine |
| `MediaCapabilities` | Verified/unknown output state | Engine availability from build; native HDR/audio output unverified |
| `VideoColorInformation` | Typed source-only color/HDR descriptor | mpv `video-params` tokens, luminance and dynamic scene metadata if exposed |
| `AudioInformation` | Source audio descriptor | Engine-observed codec, channel layout, rate, format; spatial UNKNOWN until proven |
| `AudioOutputInformation` | Output audio descriptor | Reported output driver, format, channels, transport; no AVR guarantee |
| `AudioDevice` | Output endpoint | Discovered ID/label, not a codec capability declaration |
| `MediaProbe` | Future async media inspection | Still returns `ENGINE_UNAVAILABLE` |
| `MediaDescription`, `MediaTrack`, `MediaChapter` | Metadata models | Live per-session tracks/chapters (standalone probe still reserved) |
| `PlaybackOptions` | Audio/HDR/seek and output policy | Explicit PCM mixing, receiver-bound passthrough; unsupported requests rejected |
| `MediaKitGtk.MediaView` | Video display | GTK GLArea + libmpv embedded OpenGL API, optional caller-provided ICC blob |
| `MediaKitGtk.MediaControls` | Optional controls | Play, pause, stop, seek, media tracks, chapters and audio output |

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
  `max_cll_nits`, `max_fall_nits`, mastering luminance, scene peak (not
  inherently HDR10+ metadata), and the DV profile when libmpv exposes them.
- HDR10 is recognized from PQ transfer; HDR10+ classification requires an
  explicitly confirmed `hdr10plus-metadata-confirmed` boolean in the typed
  source dictionary. The current libmpv adapter does not supply this key,
  so ordinary PQ streams remain HDR10 rather than being falsely labeled.
  The library cannot yet guarantee recognition of HDR10+ dynamic metadata. HLG requires HLG transfer. Dolby Vision requires an observed
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
  public remote control is not supported in Stage 5.

## Errors and capability claims

Missing libmpv in a deliberately disabled build produces
`MediaError.ENGINE_UNAVAILABLE` for playback. Native initialization, load,
OpenGL and command errors are propagated rather than replaced by success.

`MediaCapabilities.playback_engine=AVAILABLE` means an mpv-backed build is
present, not that a particular output device/codec has been demonstrated.
`native_hdr`, `encoded_audio` and `hdr_presentation` remain UNVERIFIED; Dolby
Vision/Atmos/DTS:X or hardware GPU acceleration must not be claimed based on
source tags or library availability alone.

## Stage 5 audio interfaces

`PlaybackOptions.audio_policy` defaults to `AUTO` (PCM; passthrough disabled).
`pcm_channel_policy` defaults to `SYSTEM_DEFAULT`; `PRESERVE_SOURCE` requests
`audio-channels=auto`. `audio_device_id` defaults to `auto` and
`passthrough_codecs` defaults to `NONE`. `PREFER_PASSTHROUGH` requires an
explicitly enumerated device ID (not `auto`) and a receiver-approved subset of
`AC3`, `EAC3`, `TRUEHD`, `DTS` and `DTS_HD`. An unsupported policy is rejected
before touching the current session. Options are copied at engine creation.

`MediaSession.source_audio` returns decoded-source `AudioInformation` metadata:
source codec, sample rate, channel count, channel layout and sample format.
`MediaSession.audio_output` returns `AudioOutputInformation`: requested engine
output device, active driver, output rate/layout/count and sample format.
Its `AudioTransportState` reports `UNKNOWN`, `DECODED_PCM`, or
`ENCODED_OBSERVED`. The latter describes **only libmpv's output sample format**.
Receiver-specific formats and 3D audio object decoding remain unverified.

`MediaSession.audio_devices` is a read-only `GListModel` of `AudioDevice`
entries, including the `auto` default when a native session is open. Select a
PCM endpoint via `select_audio_device(id)`; the command can be rejected later
by libmpv and report `operation_failed`. In passthrough mode, switching to a
new receiver is prohibited until the session is reopened with that receiver's
approved codec allowlist. Events: `source_audio_changed`,
`audio_output_changed`, and `audio_devices_changed`.

## Stage 6: discs and standalone M2TS

`MediaSource.for_transport_stream(path)` is a standalone MPEG transport-stream
source. `MediaSource.for_disc(path, DiscKind.BLURAY, DiscStartMode.LONGEST)`
and the DVD equivalent explicitly identify an optical-disc source or ISO. The
`DiscStartMode.PLAYLIST` selector accepts numeric MPLS IDs on Blu-ray only.

`MediaSession.disc_titles` exposes `DiscTitle` objects;
`select_disc_title(index)` validates the current inventory.
`disc_menu_supported` and `disc_menu_active` are separate, observed states.
`navigate_disc_menu(DiscMenuAction)` raises a descriptive error where the
required native menu support is not present.

See `docs/disc-playback.md` for source selection and compatibility constraints.

## Stage 7 video presentation

- `PlaybackOptions.tone_mapping`: `ToneMappingAlgorithm` (`AUTO`, `BT2390`,
  `MOBIUS`, `HABLE`), applied to the *next* engine instance.
- `PlaybackOptions.video_quality`: `VideoQualityPolicy` (`BALANCED`,
  `HIGH_QUALITY`); high quality selects bounded debanding before engine init.
- `OpenGlOutput.rendering_information`: cached renderer-local framebuffer
  and ICC status, refreshed only after a draw, resize or ICC update.
- `OpenGlOutput.invalidate_framebuffer()`: explicit cache invalidation for a
  host replacing its bound GL target without changing dimensions.
- `MediaKitGtk.MediaView.rendering_information`: matching GTK-facing snapshot.
  `rendering_information_changed` notifies consumers of actual changes.
- `VideoRenderingInformation.has_ten_bit_framebuffer`: RGB bits only; **never**
  infer monitor HDR, compositor output, `gpu-next` or Dolby Vision FEL.
- `MediaCapabilities.embedded_gpu_next` is `UNAVAILABLE` for this release;
  native HDR and Dolby Vision FEL remain unverified.

## Optional gpu-next windowed renderer (0.7.1)

- `GpuNextProbe.probe_async(Cancellable?)` asynchronously checks for mpv 0.42+
  in a Wayland session. An executable passing this check **can only attempt**
  advanced rendering, not prove native monitor HDR or FEL output.
- `GpuNextCapabilities` exposes `can_launch`, `version`, `executable`,
  `wayland_session`, `native_hdr`, `embedded_gpu_next`,
  `dolby_vision_fel`, `hdr10_plus_metadata_output`. Unverified states must
  not be promoted to AVAILABLE based on file metadata or version.
- `GpuNextLaunchOptions` provides `color_hint_mode` and `allow_network`, plus
  `build_arguments()` for a validated, non-shell launch. Only files and
  optionally HTTP(S) URLs are supported; Blu-ray and DVD require separate
  device handling and are rejected.
- `GpuNextWindow.open_async(source, options?, cancellable?)` creates a
  **separate Wayland window** using the system mpv executable. It owns the child
  process and signals `finished(successful, exit_status)` on exit. `stop()`
  requests termination; `close()` forcibly releases an active child.
  Launch success is not equivalent to working playback or native HDR.

The existing `MediaSession`, `OpenGlOutput` and `MediaView` contracts remain
unchanged. The optional external renderer has independent transport state and
must not be mistaken for an embedded GTK widget or a validated AV pipeline.

## Stage 7.2 — separate gpu-next transport and status

- `GpuNextWindow.open_async(source, options?, cancellable?)` returns after mpv
  has accepted its first command on a private, per-player Unix-domain socket,
  not merely after process spawning. It refuses concurrent opens and closes a
  partially launched child on failure. `ready` is observable separately from
  `running`; clients must check `ready` before sending control requests.
- `GpuNextWindow.set_paused_async(bool, cancellable?)` is an idempotent remote
  state request. `seek_async(int64 position_us, cancellable?)` sends an absolute
  accurate seek after rejecting negative targets. Both acknowledge mpv command
  acceptance, not screen scanout or physical output.
- `GpuNextWindow.query_status_async(cancellable?)` returns a new immutable
  `GpuNextPlaybackStatus` with pause state, microsecond position, current VO,
  **source** primaries/transfer, and `native_hdr=UNVERIFIED`. Missing optional
  properties are empty or -1, never promoted to an output guarantee.
- Commands are JSON-encoded, bounded by a five-second per-command watchdog,
  and sent only over a socket beneath a unique mode-0700 temporary directory.
  Unsolicited events are skipped until the matching request ID is seen.
- `GpuNextLaunchOptions.tone_mapping` selects `AUTO`, `HDR10_PLUS` (ST 2094-40)
  or `DOLBY_VISION` (ST 2094-10). This influences mpv/libplacebo internal tone
  mapping only; it does **not** transmit dynamic HDR metadata to the display.
- `MediaKitGtk.GpuNextControls` is a separate neutral XML-backed control
  widget for this standalone process (pause/resume, ±10 seconds, refresh). It
  must not be confused with the embedded `MediaControls`/`MediaSession` pair.

### Version/runtime constraints

The compositor and connected monitor must support native HDR negotiation for
native HDR; detecting BT.2020/PQ source metadata or a gpu-next VO alone proves
neither native HDR scanout nor Dolby Vision Profile 7 FEL reconstruction.
The GTK-embedded `MediaView` remains its previous SDR libmpv OpenGL view.

## Stage 7.3 — experimental embedded gpu-next compatibility

A stock libmpv build still renders through the existing `MediaSession`
`create_opengl_output()` and `MediaKitGtk.MediaView` APIs. Experimental
embedding is **disabled by default** and must be compiled against matching
patched libmpv headers/runtime through
`-Dexperimental_embedded_gpu_next=true`. It requires the unmerged symbolic
`MPV_RENDER_PARAM_BACKEND` parameter; Meson rejects missing headers.

- `MediaKit.MediaSession.supports_experimental_gpu_next_embedding()` reports
  compile-time support only. It is not a GPU, swapchain, or HDR test.
- `MediaKit.MediaSession.create_experimental_gpu_next_output()` creates an
  explicit gpu-next OpenGL attachment or returns an error. No silent fallback.
- `MediaKitGtk.MediaView.experimental_gpu_next` requests that same path on an
  attached/realized view. Changing it detaches the previous GL endpoint first.
- `VideoRenderingInformation.backend` identifies
  `libmpv-gpu-next-experimental` when used. `presentation` stays `UNVERIFIED`
  for this path even with a submitted frame or 10-bit local framebuffer.
- `GpuNextPlaybackStatus.output_primaries` and `output_transfer` describe
  `video-out-params` reported by the separately windowed mpv process when
  available. These values are distinct from `source_primaries` and
  `source_transfer`. They do **not** establish actual monitor EOTF or HDMI
  dynamic metadata signaling. The existing constructor remains available;
  the new `.with_output(...)` constructor adds the observations.

The draft upstream interface is experimental and **not suitable for the normal
Debian package**. The default libmpv renderer and all existing playback APIs
remain unchanged. See `docs/verification-stage7-embedded.md`.

## Experimental GTK PQ API (0.7.4)

- `HdrOutputPolicy.EXPERIMENTAL_PQ_TEXTURE`: requests a PQ float-texture
  renderer on the next opened source. It is intentionally separate from
  `PREFER_NATIVE`, which still fails when native display HDR is unverified.
- `ColorOutputTarget.EXPERIMENTAL_BT2020_PQ` reflects the **selected engine
  output target**, not the compositor EOTF. The target is frozen for the
  active source even if caller-owned `PlaybackOptions` are subsequently edited.
- `MediaKitGtk.HdrMediaView`: an optional GTK widget compiled only with
  `-Dexperimental_gtk_pq=true` and the patched `gpu-next` interface. Its
  `session` references the current playback source; `pq_texture_submitted`
  means only that a color-tagged frame was passed to GDK. The constant
  `presentation=UNVERIFIED` explicitly avoids implying native monitor HDR.
- The normal `MediaKitGtk.MediaView` refuses PQ sessions to avoid showing
  unconverted PQ pixels on an SDR GL framebuffer.
- Native `HdrFrame` is an implementation detail and is not a public VAPI/GIR
  or installable header contract. Source compatibility with released Core and
  default GTK APIs is preserved.

## Stage 7.5 — verified floating-point framebuffer contract

- `OpenGlOutput.render_pq_frame(width_px, height_px)` is distinct from the
  unchanged SDR `render_current_frame(...)` and is used only by `HdrMediaView`.
- Native `mediakit_renderer_render_pq()` validates a complete, non-default
  OpenGL framebuffer with RGB **floating-point** attachment components of at
  least 16 bits each, and passes `GL_RGBA16F` to libmpv rather than an implicit
  internal format. It rejects a non-patched renderer or an SDR-configured engine.
- The original render entry point refuses PQ-configured engines, including
  when called through a Vala consumer outside `MediaView`.
- `MediaCapabilities.embedded_gpu_next` is `UNAVAILABLE` on default builds or
  `UNVERIFIED` when support was compiled in. Only successful, independently
  qualified rendering could justify `AVAILABLE`.
- The GTK bridge restores draw and read framebuffer bindings independently,
  fails on GPU allocation or synchronization errors, and retains its previous
  public widget API. No success here implies native HDR display output.

### Stage 7.6 experimental HDR texture backpressure

`MediaKitGtk.HdrMediaView` retains the public API and opt-in prerequisites of
Stage 7.5. It now bounds published-but-unreleased floating-point frame
textures to three per view. A transient `G_IO_ERROR_WOULD_BLOCK` from the
private frame bridge is handled internally without emitting a fatal render
failure. The current cached texture remains visible until an engine update can
supply a new frame. GTK's accepted texture storage type and color-state tag
must match RGBA16F and BT.2100/PQ. The `presentation` property still returns
`UNVERIFIED`; this is intentional and does not assert native HDR scanout.

### Stage 7.7 private HDR driver and state checks

No new public GObject/GIR/VAPI contract is introduced. Inside
`native/gtk/hdr-frame.c`, texture allocation verifies driver-reported RGBA16F
storage through a small, GTK-independent C11 format contract. The GL renderer
restores the caller's viewport, scissor, blend factors and clear color on both
success and cancellation/failure. The `HdrMediaView` remains opt-in and can
emit `rendering_failed` when driver capabilities are insufficient. This does
not certify monitor HDR, FEL reconstruction or dynamic HDR signaling.
