# Testing and release qualification

## Scope

Only Stage 1 contracts are tested. No media benchmarks, frame-accuracy tests,
hardware outputs, codec fixtures or long-running decoder stress tests are
meaningful until Stage 2 exists. Avoid creating them prematurely.

| Test executable | Suite | Coverage |
| --- | --- | --- |
| `test-core-contract` | unit | File and URI source identity; rejected URI scheme; unavailable engine and conservative capabilities; async open error/close; cancellation |
| `test-gtk-contract` | integration | GTK template creation and shared session assignment/replacement |

## Commands

```sh
meson setup build-core -Dgtk=false -Dexamples=false -Dtests=true
meson compile -C build-core
meson test -C build-core --print-errorlogs

meson setup build -Dgtk=true -Dexamples=true -Dtests=true
meson compile -C build
meson test -C build --print-errorlogs

python3 tools/check_source_docs.py
python3 tools/check_structure.py
```

The GTK integration test requires a usable GDK backend and runs with
`GDK_BACKEND=headless`. If that backend is absent in the target GTK version,
use an explicit compositor/virtual display qualification and record the
result rather than silently treating the GTK test as passed.

Use `-Dintrospection=enabled` for mandatory typelib builds. On a target with
the necessary development packages, also verify generated `.h`, `.vapi`,
`.gir`, `.typelib`, `.pc`, `.deps` files and that a standalone consumer can
link only Core with no GTK dependencies.

## What must be reported

Build, native tests, GTK tests, introspection and Debian package checks each
receive separate **passed**, **failed** or **not run** status. A source-only
static check cannot substitute for Vala/Meson compilation. Any unavailable
backend, renderer, test fixture, display or toolchain must be disclosed.

## Next qualification milestones

When Stage 2 creates an actual playback engine, add small representative
fixtures for load/play/stop, seeking, tracks and subtitles, cancellation and
hardware-decoding fallback. Only after HDR and encoded audio outputs work
should tests/benchmarks for native HDR/Atmos/DTS:X be added, with actual
monitor/receiver confirmation rather than container metadata alone.
