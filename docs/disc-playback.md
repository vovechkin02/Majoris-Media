# Disc and transport-stream playback — Stage 6

## Source handling

- `MediaSource.for_transport_stream(path)` preserves local file identity and uses
  the **ordinary media loader**. `.mts`, `.ts`, and `.m2ts` do not require a
  mounted disc, `BDMV`, `MPLS` or `VIDEO_TS` directory. Existing `for_path`
  and `for_uri` methods are unchanged.
- `MediaSource.for_disc(path, kind, start, selection)` accepts a **local** DVD
  or Blu-ray drive/device, extracted disc directory or explicitly identified
  ISO image. `kind` must be `DVD` or `BLURAY`; it is never inferred from a
  generic `.iso` extension. The source's public `uri` remains a local file URI.
- To play a Blu-ray MPLS playlist, choose `DiscStartMode.PLAYLIST` with the
  numeric `.mpls` filename; this generates `bd://mpls/NNNNN` internally.
  A numeric `DiscStartMode.TITLE` selects an engine title index, not an MPLS
  filename. DVD playlists are rejected.

## Backend configuration

The private `MpvBackend` passes an absolute local device path through
`mediakit_engine_prepare_disc`. The native adapter sets the `options/dvd-device`
or `options/bluray-device` property before loading. It then queues a *separate*
`dvd://...` or `bd://...` source via the existing cancellation-safe loader.
The device filename is **never concatenated** with the media protocol URL.

Titles are exposed as typed `DiscTitle` snapshots via `MediaSession.disc_titles`.
libmpv's `edition-list` / `edition` properties are read where supported; older
builds may expose `disc-title-list` / `disc-title`. Titles can legitimately be
absent or incomplete on some disc images or backends. Chapter navigation and
source audio/subtitle selection remain the existing Stage 3 contracts.

## Conditional interactive menus

mpv **0.42 and newer** introduced the `discnav` command and HDMV/BD-J menu
navigation. Stage 6 gates `DiscStartMode.MENU` and navigation requests when
an older engine is detected. DVD menu navigation and Blu-ray menus have different
behavior: Blu-ray generally needs to be opened in menu mode; a movie started
without menu mode cannot necessarily return to BD-J/HDMV. Runtime
`disc-menu-active` is reported separately from basic menu support. The GTK view
routes arrows, Return, Escape and F10 only while the disc is eligible.

BD-J Java dependencies, libbluray compilation options, the actual disc structure
and optical drive are outside this library's control. AACS/BD+ encrypted discs
may require licensing, software and/or keys not provided by this project.
This stage does **not** decrypt copyrighted discs or bypass access control.

## Platform and QA limits

The bundled synthetic transport stream checks demuxing. No protected or real
Blu-ray/DVD/UHD images are bundled. The source-oriented smoke test cannot prove
commercial-disc compatibility, real disc menus, PGS subtitle correctness,
UHD HDR presentation, seamless branching or mechanical-drive behavior.
Test those independently on hardware with an appropriate libmpv build.
