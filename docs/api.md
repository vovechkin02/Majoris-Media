# Public API and semantics (Stage 1)

## Stability

This is a pre-release `0.1.0` API. Libraries are named
`libmajoris-media.so.0` and `libmajoris-media-gtk4.so.0`; Vala packages are
`majoris-media-1` and `majoris-media-gtk4-1`; introspection namespaces are
`MediaKit-1.0` and `MediaKitGtk-1.0` when typelib tools are available.
Do not equate the GIR namespace version with a stable 1.0 release.

## Public surface

| Type | Meaning | Current behavior |
| --- | --- | --- |
| `MediaSource` | Source identity (file, URI) | Constructs without disk/network I/O |
| `MediaSession` | State, source and control surface | Open/play/pause/stop/seek fail explicitly |
| `MediaProbe` | Asynchronous source inspection | Fails engine-unavailable |
| `MediaDescription` | Source, duration and read-only track/chapter models | Created only by future probing adapter |
| `MediaTrack`, `MediaChapter` | Metadata descriptors | Construction only |
| `VideoInformation`, `AudioInformation` | Typed video/audio source properties | Defaults indicate unknown data |
| `MediaCapabilities` | Runtime and output availability | No claimed HDR or passthrough |
| `PlaybackOptions` | Requested output/seek policies | Stored, not applied |
| `MediaView` (`MediaKitView` GType) | Embeddable Gtk.Box and state overlay | No frame rendering yet |
| `MediaControls` (`MediaKitControls` GType) | Optional Gtk.Box transport strip | Play button disabled |

## Time, color and audio contracts

- `seek(position_us)`, `MediaDescription.duration_us` and
  `MediaChapter.start_us` all use signed 64-bit **microseconds**.
- Unknown duration is `-1`; a zero position is the source beginning.
- `HdrFormat` describes source information **only**; `HdrPresentation` describes
  the actual display output status. They cannot be substituted.
- `SpatialAudioFormat.DOLBY_ATMOS`/`DTS_X` is a source metadata classification,
  not a statement that object-audio rendering or encoded passthrough succeeded.
- `AudioOutputPolicy.PREFER_PASSTHROUGH` and
  `HdrOutputPolicy.PREFER_NATIVE` are requests; hardware capability negotiation
  must independently determine the actual output.
- `CapabilityStatus.UNVERIFIED` explicitly means no output proof exists.

## Ownership and thread context

A `MediaSession` owns its private backend and retains its selected `MediaSource`.
A `MediaView`/`MediaControls` retains the assigned session until unbound or
disposed. Widgets disconnect state callbacks before dropping that reference.
`MediaDescription.tracks` and `.chapters` are exposed as read-only
`GLib.ListModel`s. A headless consumer never instantiates GTK types.

Session mutation must occur on its owning main context; synchronization
between external threads is a future API decision. Async opening is
cancellable. A late response from a closed or superseded request cannot change
the newer visible session state.

## Errors

`MediaError.INVALID_SOURCE` rejects unsupported source identity.
`MediaError.INVALID_ARGUMENT` rejects invalid operations such as negative seek.
`MediaError.ENGINE_UNAVAILABLE` is the expected Stage 1 response to all media
operations. A failed `open_async` leaves the current source and last error
available for diagnostics while moving to `ERROR`. `close()` returns to `EMPTY`.
A pre-canceled open returns `G_IO_ERROR_CANCELLED` without a state change.

The interface reserves `UNSUPPORTED` and `PLAYBACK_FAILED` for truthful
backend errors in future stages. It never substitutes success for a missing
renderer, decoder, passthrough device or output feature.
