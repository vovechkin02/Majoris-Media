# Stage 1 verification record — 2026-11-20

This archive was created from the supplied essentially empty Majoris Media
repository, with the supplied Majoris Image 2.0.1 source and Majoris Cross-Project
Engineering Standards 1.8 used as structural and style references. No VLC
implementation code has been incorporated.

## Completed source verification

- **Passed:** XML documents parse, their GResource entries and template GType
  names match, and all declared Core/GTK Vala sources appear in Meson targets.
- **Passed:** Static separation checks confirm that Core does not reference GTK
  and that the GTK library is conditional on the `gtk` Meson option.
- **Passed:** The project-owned Vala declaration-summary scan finds summaries
  for all declarations selected by the checker. This is a best-effort static
  checker rather than a Valadoc parser or proof of documentation quality.
- **Passed:** Python static checker syntax and archive integrity.

## Toolchain-gated checks — not run

- **Not run:** Meson configure and compile, including Core-only and GTK-enabled
  profiles; this workspace does not have `meson`, `valac`, or GLib/GTK dev headers.
- **Not run:** Vala/GTK native unit/integration tests, GIR typelib generation,
  Debian package build, ABI checks and installed-consumer compilation.
- The attempt to install build dependencies failed because package indexes
  were unavailable from the network in this execution environment.
- **Not run:** Playback, codecs, HDR, Dolby Vision, Atmos and DTS:X. These are
  outside Stage 1 and no engine is integrated.

## Required local qualification before accepting compilation

Install the Debian 13 toolchain and run the commands in `docs/TESTING.md`.
Resolve compiler/API errors if they appear and check both library target
installations, resource loading, and Debian package contents before integration
into the Majoris ISO.
