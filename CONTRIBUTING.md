# Contributing to Majoris Media

Follow the bundled [Majoris Cross-Project Engineering Standards v1.8](docs/engineering-standards-v1.8.md).
This applies to handwritten public/private declarations, ownership, GoF
pattern intent, Meson structure, Vala inferred locals, GTK XML templates,
and source documentation coverage. Use American English in project-authored
identifiers and documentation; retain upstream names when interoperability
requires them.

## Development contract

- Maintain Core's complete independence from GTK4 and libadwaita.
- Place GTK presentation in `src/gtk`, native engine integrations in `native/`,
  and policy/state within `src/core`.
- Never report an unvalidated HDR/codec/HDMI capability as supported.
- Keep errors, cancellation, output ownership and GObject signal lifetimes
  explicit. Preserve published API/ABI unless a versioned migration is approved.
- Keep GUIs declarative with `.ui` XML, no application toolbars in reusable
  widgets, and avoid hardcoded theme styling.
- Only introduce GoF roles when an actual variation exists; record their
  participants and verification in `docs/architecture.md`.

## Verify changes

```sh
python3 tools/check_source_docs.py
python3 tools/check_structure.py
meson setup build-core -Dgtk=false -Dexamples=false
meson compile -C build-core
meson test -C build-core --print-errorlogs
meson setup build -Dgtk=true
meson compile -C build
meson test -C build --print-errorlogs
```

Review C/Vala warnings and artifact installation. A declaration-documentation
scan supplements, never replaces, the compiler and Valadoc.
