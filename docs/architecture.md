# Architecture — Stage 2 (0.2.0)

## Component and dependency structure

```text
       Media Player, Files, other consumers
                  |            |
                  v            v
          MediaKitGtk          MediaKit Core
          GtkGLArea     <------ MediaSession (Facade)
          MediaControls            |
                              PlaybackBackend (Strategy)
                                /           \
                      MpvBackend          UnavailableBackend
                          |
                 C GObject engine adapter
                   libmpv client API
                      /       \
              libmpv player    libmpv OpenGL render API
                   |                    |
              FFmpeg/audio          GtkGLArea framebuffer
```

The Core depends on GLib/GIO and, when `-Dmpv=enabled`, libmpv and libepoxy.
It does **not** link GTK. The optional GTK4 library depends on Core, GTK4, and
embedded XML resources. `MediaView` does not own a top-level window, playlists,
or an application's styling policy. libmpv drives demux/decode/clocks/audio;
MediaKit does not reimplement these subsystems.

## Operational ownership

Each `MediaSession` owns exactly one `PlaybackBackend`. Empty sessions use the
non-playing placeholder without creating libmpv handles; a real engine is
constructed only on `open_async`. Replacing a source
creates a fresh backend/engine instance, avoiding confusion between stale
`FILE_LOADED`/`END_FILE` events and the next source. Before releasing the
old engine the session replaces its backend and emits `output_changed`;
consumers detach old OpenGL renderers and attach a new one, while both engine
objects are still alive. The previous backend is then closed. A canceled
open's callbacks cannot change a newer session generation.

The native `MediaKitEngine` owns one libmpv handle and at most one active
`MediaKitRenderer` (nonowning link); the renderer strongly retains its engine.
The GTK wrapper `OpenGlOutput` holds the native renderer and frees it with
the rendering GL context current. GTK view/controls own signal subscriptions
only while bound to a session. All subscriptions are disconnected on rebinding.

## Threading and GL context constraints

- libmpv may invoke its wakeup/update callbacks on worker threads. Native C
  schedules coalesced idle sources for the engine's owning main context; it
  never calls GTK directly from worker callbacks.
- Native open completion uses `GTask` and waits for `MPV_EVENT_FILE_LOADED`.
  A command being queued does **not** qualify as a successfully loaded file.
- libmpv's OpenGL render context is created only after GTK's GLArea has a
  current context. `mpv_render_context_render` targets GTK's currently bound
  framebuffer, with physical-pixel width/height, avoiding CPU readback.
- The initial implementation deliberately does **not** enable
  `MPV_RENDER_PARAM_ADVANCED_CONTROL`. That mode imposes additional strict
  render/core synchronization and update-callback obligations which must be
  designed and measured separately. Frame notifications are dispatched to GTK
  and the renderer invokes `mpv_render_context_update()` before drawing.
- One active video renderer per session: libmpv currently supports only one
  render context per player core. A second view must use a distinct session.
- GTK GLArea unrealization/source replacement must free the render context
  *before* its GL context is destroyed. Rendering on an unrelated thread or
  context is prohibited.
- Core may be used without GTK for audio, source lifecycle or future probes;
  video without an initialized GL output is not guaranteed to decode/display.

## Design patterns and justification

| GoF pattern or idiom | Participants | Actual variation and contract |
| --- | --- | --- |
| Facade | `MediaSession` | Stable consumer commands over native engine lifecycle |
| Strategy | `PlaybackBackend`, `MpvBackend`, `UnavailableBackend` | Optional engine availability without consumer-side backend checks |
| Adapter | Native C GObject engine and VAPI | Converts libmpv commands, errors, events, threads and ownership into GLib contracts |
| Observer (GLib idiom) | Session and OpenGL output signals | GTK subscribers observe changes without a second custom event bus |

Pattern names are justified by roles, not decorative class hierarchies. The
renderer is a context-bound resource wrapper, not an unrelated Abstract Factory.
Private C binding types never appear in the installed public API. Avoid
per-frame dynamic dispatch beyond the unavoidable single GL renderer call.

## Known limitations and next steps

This prototype has not been compiled or run on Debian in the authoring
container. It does not provide dedicated media probing, enumerated subtitle
tracks, playlists, disc navigation, verified hardware decode interop,
HDR/gpu-next/Dolby Vision Profile 7 FEL output, or HDMI encoded passthrough.
These require their own implementation and validation stages; see formats.md.

Potential performance work after baseline qualification: move mpv initialization
and teardown off the GTK main thread where measured to block, adopt advanced
render controls only with correct synchronization, and resolve Wayland/X11 GPU
interop when specific hardware warrants it. Do not optimize speculatively.
