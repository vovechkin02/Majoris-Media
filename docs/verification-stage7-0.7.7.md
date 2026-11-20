# Stage 7.7 verification — GPU storage and state integrity

**Date:** November 21, 2026
**Baseline:** Supplied Majoris Media 0.7.6 source archive
**Artifact:** Majoris Media 0.7.7 source ZIP
**Status:** Source corrections and independent C11 tests completed; embedded HDR
and Stage 7 hardware qualification **remain incomplete**.

## Changes made

- Rejects an OpenGL texture unless driver queries confirm sized `GL_RGBA16F`,
  four `GL_FLOAT` component types, and 16-bit R, G, B and A storage. This
  avoids turning an application-provided GTK color tag into a false statement
  about actual GPU allocation. Implemented behind a private, pure-C11 check.
- Requires desktop OpenGL 3.2 or later for experimental floating-point GL
  output. An unsupported GLES/old GL context produces a useful error instead
  of proceeding with unavailable GL texture or synchronization functions.
- Saves and restores the host's draw/read FBOs, viewport, scissor rectangle,
  blend functions, clear color and scissor/blend enable states across libmpv's
  HDR draw, including abort paths. This covers the state mpv's OpenGL render
  API explicitly does not promise to preserve.
- Maintains the previously bounded three-texture allocation policy. Invalid
  frame-budget accounting now fails fast even in optimized NDEBUG builds.
- Keeps the format-checking symbol private, with no public API/ABI or
  application-visible changes to Core, GTK, default SDR rendering, or options.

## Checks actually executed in this authoring environment

| Test | Result | Evidence scope |
| --- | --- | --- |
| GCC C11 frame-budget test (with `-DNDEBUG`, warnings as errors) | **Passed** | Slot cap, lifetime, concurrent reservation |
| Clang C11 frame-budget test (same strict flags) | **Passed** | Independent compiler check |
| GCC C11 pixel-format contract (`-DNDEBUG`, warnings as errors) | **Passed** | Full RGBA16F acceptance, normalized/8-bit rejection |
| Clang C11 pixel-format contract (same strict flags) | **Passed** | Independent compiler check |
| Python source documentation checker | **Passed** | 717/717 checked Vala/C definitions |
| Python repository structure checker | **Passed** | Meson inventories, XML, Core/GTK separation, text hygiene |
| `ffprobe` on the included HDR fixture | **Passed** | HEVC, `yuv420p10le`, BT.2020, SMPTE ST 2084 transfer |
| ZIP integrity and Debian executable-bit check | Verified at packaging | Archive completeness and permissions |

The above checks do **not** demonstrate successful GTK, libmpv, or OpenGL
compilation, rendering, colorimetry, GPU synchronization, native scanout, or
Dolby Vision reconstruction.

## Explicitly not run or not implemented

- **Full Meson/Vala/GTK/libmpv native compilation:** Not run. The authoring
  container lacks `valac`, `meson`, GLib/GTK/libmpv development headers, and
  cannot resolve Debian package mirrors for installation.
- **Experimental GTK/PQ end-to-end playback:** Not run. Requires GTK 4.16+,
  a matching patched libmpv for the unmerged `MPV_RENDER_PARAM_BACKEND` ABI,
  a compatible GPU/driver, and actual GTK/Wayland runtime.
- **Native HDR monitor presentation:** Unverified. A correctly formatted,
  PQ-tagged GTK texture can still be tone-mapped or converted by Mutter.
- **Dolby Vision Profile 7 FEL:** Reconstruction is not qualified with real
  reference content or rendered-image comparisons.
- **HDR10+/Dolby Vision dynamic display signaling:** Not implemented as an
  interoperable Wayland/GDK-to-display-link metadata path. The internal
  ST 2094 tone-mapping options do not transmit HDMI dynamic metadata.

## Required next release gates on Majoris/Debian hardware

1. Run **both** ordinary and patched builds on Debian 13, including Vala
   compilation, GTK realization and all Meson tests.
2. On an actual Wayland GPU display, exercise source changes, resizing,
   repeated realization/unrealization, slow compositing and GL-context loss;
   verify frame-budget limits and absence of stale textures/leaks.
3. Run HDR10/HLG/PQ frame readback and external display measurements, and
   verify Mutter's negotiated color state rather than relying on pixel format.
4. Verify Dolby Vision P7 MEL/FEL through trusted reference images and an
   independently validated decoder before asserting reconstruction correctness.
5. Investigate a supported upstream embedded gpu-next interface. Maintain the
   default SDR renderer until the patched path can pass the release gates.

**Release interpretation:** Stage 7.7 closes a measurable native source-level
precision and state-management gap. It **does not** close the upstream and
hardware dependencies of the original Stage 7 specification.
