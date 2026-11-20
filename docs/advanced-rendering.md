# Advanced rendering design — Stage 7

## Established architecture

The existing `MediaKit` headless session owns a per-source libmpv engine and its
GTK presentation endpoint is a `MediaKitGtk.MediaView` based on `GtkGLArea`.
The renderer is created on a current GL context and is detached before the host
context is destroyed. Stage 7 **keeps the stable rendering API** and does not
introduce a new renderer pretending to implement an unmerged upstream feature.

### Supported implementation

- `PlaybackOptions.tone_mapping` selects one of `AUTO`, `BT2390`, `MOBIUS`,
  `HABLE`. These are legacy libmpv/OpenGL-compatible SDR algorithms. They are
  applied *before* the mpv engine is initialized. Changing them requires
  opening a new source; there is no silent mid-playback reconfiguration.
- `PlaybackOptions.video_quality` selects normal processing or a bounded
  debanding pass. High quality has an added GPU cost and is opt-in.
- `MediaKit.OpenGlOutput.rendering_information` captures the actual GL color
  channel sizes and `MPV_RENDER_PARAM_DEPTH` value used for dithering. Sampling
  occurs on the first successful draw, after a framebuffer size change, or
  after an accepted ICC profile change, **not on every video frame**.
- `MediaKitGtk.MediaView.rendering_information_changed` mirrors this data to
  GTK consumers. Unmap, source replacement, and detach clear the old snapshot.
- `VideoRenderingInformation.icc_profile_active` reports only the result of a
  successful libmpv ICC *configuration call*, **not** proof of a colorimetric
  match to a monitor. The host must supply and maintain the current display ICC.
- The output remains an explicitly configured BT.709/BT.1886 **SDR** render
  target. `has_ten_bit_framebuffer` indicates a local GL texture format only;
  it never implies that the compositor scans out HDR, or that source metadata
  is preserved through all layers.

### Not implemented or not verified

| Area | Stage 7 status | Reason |
| --- | --- | --- |
| SDR conversion / tone mapping | Source configured; hardware qualification pending | libmpv OpenGL API used |
| Actual GL channel precision | Source instrumented; runtime values pending | Must query the live GTK framebuffer |
| Native Wayland HDR / scRGB / 10-bit scanout | Not implemented | Requires GTK/GDK color-state and Mutter/display pipeline integration |
| Embeddable `gpu-next` / libplacebo | Not implemented | Upstream libmpv feature is still under review |
| Dolby Vision Profile 7 MEL/FEL | Not validated in embedded view | `gpu-next` standalone support does not imply embedded support |
| HDR10+ dynamic native signaling | Not implemented | Renderer and compositor need appropriate HDR color metadata handling |
| Cross-monitor HDR/ICC transition | Partially supported for host ICC | Host must reselect the display profile and validate output |

## Advanced renderer boundary for subsequent implementation

The `MediaKitNative.Renderer` C adapter exclusively owns engine-specific render
contexts, update callbacks, GL-thread resource release, and color-profile
application. If an upstream supported `gpu-next` or external libplacebo
integration becomes available, add an explicitly negotiated native renderer
*behind that boundary*, with a separate target color-state contract. Do not
expose libplacebo pointers in the public Vala/GIR API or copy the upstream
codec, synchronization, and scaling engine.

The renderer must negotiate its swapchain surface, color primaries, transfer,
output precision, display peak and actual Wayland color-management protocol
rather than guessing from source files or a screen's EDID. GDK HDR support and
compositor support must both be confirmed. A source's HDR10, HDR10+, HLG or DV
metadata is a **different** capability from native presentation. Profile 7
FEL needs real enhancement-layer reconstruction tests, not just codec probing.

## Qualification matrix on real Majoris/Debian hardware

1. Build a normal GTK4/libmpv release; inspect the installed mpv/libplacebo
   build, GPU driver, Wayland session, GTK and Mutter versions.
2. Verify SDR baseline in a managed BT.709 monitor pipeline with ICC enabled
   and disabled; measure grayscale, primaries, color cast and clipping.
3. With the included HDR10 reference file, compare SDR tone-map algorithms,
   histogram clipping, banding, frame drops, GPU memory, and seek latency.
4. Test the same fixture on 8-bit, 10-bit and floating-point GTK framebuffers;
   record `VideoRenderingInformation` but do **not** interpret its depth as HDR.
5. Test a real HDR10/HLG/HDR10+ screen using a *separate, actually supported*
   HDR-capable path once integrated; confirm Wayland color-state negotiation,
   compositor output, OS HDR settings and external signal measurements.
6. For DV 5/8 and DV 7 MEL/FEL, use licensed reference media and verify
   decoded picture, dynamic metadata, RPU handling, MEL/FEL reconstruction,
   and display output independently. Never classify "HDR10 fallback" as FEL.
7. Move the GTK view between SDR and HDR screens, change ICC profiles,
   realize/unrealize repeatedly, replace source and dispose during playback.
8. Verify frame times, A/V synchronization, error propagation, cancellation,
   direct GPU decode, and memory stability on both Mesa and supported GPUs.

## Upstream references (as inspected on 2026-11-20)

- mpv render API: <https://github.com/mpv-player/mpv/blob/master/include/mpv/render.h>
- mpv 0.42 release: <https://github.com/mpv-player/mpv/discussions/18763>
- Draft libmpv gpu-next embedding: <https://github.com/mpv-player/mpv/pull/16818>
- mpv GPU/tone mapping options: <https://mpv.io/manual/stable/>
- GTK color management: <https://release.gnome.org/47/developers/>

**Release gate:** Stage 7 is a source implementation for the SDR renderer
policy and diagnostic seam. It is not complete native HDR/FEL implementation.

## Stage 7.1 advanced external renderer — implemented in 0.7.1

Majoris now exposes `GpuNextProbe`, `GpuNextCapabilities`,
`GpuNextLaunchOptions` and `GpuNextWindow` from the GTK-independent Core.
This path uses the installed **mpv 0.42+** executable with `--vo=gpu-next`
on its **own Wayland window** and allows the engine to negotiate a native
swapchain rather than sending its HDR pixels into an unqualified GTK GLArea.

The optional engine is supervised as a distinct process, never installed as a
surreptitious substitute for `MediaView`. Source playback, seek, tracks, audio
and lifetime are **independent** of the embedded MediaSession. Hosts must close
an owned external player on teardown and must not expect GTK transport state
to control it. The demo pauses its local session after the external process is
launched to avoid two competing audio tracks.

The launcher constrains color hint selection to `target`, `source`, or
`source-dynamic` and uses `--target-colorspace-hint=auto`. The latter mode is an
experimental **HDR10 scene-luminance approximation** from dynamic metadata,
not HDMI HDR10+ metadata transport. There is no verified HDR presentation
claim without output-signal and visual qualification.

### Remaining integration gate

A production embeddable gpu-next renderer still requires an upstream-supported
libmpv API, a GTK/GDK native HDR surface color-state contract, a supported
Wayland color-management implementation, and measured end-to-end HDR output.
Do not backport the unmerged PR into the default library or use a private
numeric render parameter without an upstream ABI/ownership contract.

See [Stage 7 completion verification](verification-stage7-completion.md).

## Stage 7.2 control-plane completion (0.7.2)

The external renderer now has a private, actively probed JSON IPC endpoint,
owner-scoped cleanup, and stable play/pause/absolute-seek/status methods. A
neutral GTK4 control strip can manage this path separately from the embedded
`MediaView` playback session. HDR10+ and Dolby Vision metadata-aware tone-map
algorithms (`st2094-40`, `st2094-10`) are explicit, validated launch options.

The renderer can attempt output through native mpv Wayland `gpu-next` and the
compositor's color management, but Majoris cannot assert native HDR from the
presence of a Wayland socket, a 10-bit framebuffer, PQ source metadata, or
successful `gpu-next` startup. Full HDR10+ dynamic metadata transport and a
licensed Dolby Vision HDMI output mode are not provided by this generic
Wayland path. Profile 7 FEL reconstruction is delegated to a suitably built
mpv/libplacebo/FFmpeg stack and needs reference-picture verification.

**Still blocked:** stable, officially supported `gpu-next` embedding inside a
caller-owned GTK4 render target. Upstream mpv's Vulkan external-target request
#18343 was closed as not planned in September 2026, while #16818 remains a
proposed OpenGL embedding change. Attempting a private ABI or foreign Wayland
subsurface hack would make the library less reliable. A complete replacement
would require a substantial independently maintained decoder/render/sync
pipeline, outside a safe incremental Stage 7 completion.
