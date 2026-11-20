# Stage 3 verification record — 2026-11-20

## Source and test inventory

- **PASS:** XML templates parse; resource names and GTK template class names match.
- **PASS:** Core and GTK source inventories agree with Meson build definitions.
- **PASS:** Headless Core source has no direct GTK/GDK/libadwaita dependency.
- **PASS:** Mandatory declaration-level documentation checker: 357/357 definitions.
- **PASS:** All checked handwritten text is UTF-8, LF-terminated and has no trailing spaces.
- **PASS:** Test fixture structure verified with `ffprobe`: one video stream,
  two audio streams, one subtitle stream and two chapters.
- **PASS:** ZIP CRC/inventory check (after artifact creation).

## Native build and release checks

- **NOT RUN:** `meson setup`, compile/link or Vala/GIR/typelib generation.
- **NOT RUN:** Core and GTK integration tests; engine source-load, selection,
  buffering, hardware-decoder observation and actual frame presentation.
- **NOT RUN:** Real hardware-decoding fallback, HDR, HDMI bitstream and disc tests.
- **NOT RUN:** Debian packaging and installed consumer verification.

This authoring environment does not contain Meson, valac, GLib/GIO, GTK4 or
libmpv development libraries. Static checks do not demonstrate successful
compilation or functioning playback. Stage 3 requires a Debian 13 target build
and execution of the included Meson tests before ISO integration.

## Runtime qualification to perform

```sh
meson setup build -Dmpv=enabled -Dgtk=true -Dtests=true \
  -Dintrospection=enabled
meson compile -C build
meson test -C build --print-errorlogs
```

Then run the demo on GNOME Wayland and X11; exercise multistream selection,
subtitles, chapters, seek-before/after stop, buffering on remote HTTP media,
video decoder selection, repeated open/close, and GL context loss. Confirm
runtime and source compatibility on the actual Debian 13 image; static checks
are not a substitute for that release gate.
