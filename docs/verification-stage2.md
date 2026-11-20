# Stage 2 verification record — 2026-11-20

## Source and configuration

- **PASS:** XML templates parse and are referenced from GResources.
- **PASS:** Meson inventories include all handwritten Core and GTK Vala sources.
- **PASS:** Core Vala sources contain no GTK/GDK/libadwaita dependencies.
- **PASS:** Declaration-level documentation checker reports full coverage.
- **PASS:** LF, UTF-8 and trailing-whitespace static checks.
- **PASS:** ZIP archive CRC/inventory check after packaging.

## Checks that could not run

- **NOT RUN:** `meson setup` / `meson compile` / native symbol linking.
- **NOT RUN:** `valac` VAPI and GIR generation.
- **NOT RUN:** Unit, native media fixture and GTK GLArea tests.
- **NOT RUN:** On-device GPU decoding, HDR, multichannel audio, disc playback.
- **NOT RUN:** `dpkg-buildpackage` and installed package/API verification.

The environment did not provide Meson, Vala, GLib/GTK4 or libmpv development
packages. System package indexes and download access were unavailable. Static
checks cannot establish native build or playback success. The included source
requires a first target-machine compilation and hardware smoke test before
shipping in the Majoris ISO. Avoid claiming complete Stage 2 release readiness.
