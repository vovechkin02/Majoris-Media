# Majoris Media HDR qualification on Windows 11 and WSLg

**Date:** November 21, 2026 (Australia/Sydney)

**Source:** Majoris Media 0.7.7, checkout based on `46e47d5`.

Native HDR presentation is unsupported through the Wayland protocols advertised
by this WSLg session. The client registry has no color-management global and
does not expose a Linux DMA-BUF global. A Windows HDR setting, an HDR source
decoder, and a float attachment describe different boundaries in this pipeline.

## Environment

| Component | Observed version or capability |
| --- | --- |
| Windows | Windows 11 Pro, build 26300.9711 |
| Host GPUs | AMD Radeon(TM) Graphics, driver 32.0.21045.29003. NVIDIA GeForce RTX 4060 Ti, driver 32.0.16.2124 (WSL NVML 621.24) |
| Windows output | DXDiag reported Dell S2722QC at 3840×2160, 60 Hz, with Advanced Color enabled and `DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020` |
| WSL and WSLg | WSL 3.0.5.0, WSLg 1.0.79, MSRDC 1.2.7391, Weston revision `a7e35fdab455dce5774b43b8aff682f748307e31` |
| Linux | Debian 13.5, x86_64, kernel 6.18.58.1-microsoft-standard-WSL2 |
| Interfaces | `/dev/dxg`, `/dev/dri/card0`, `/dev/dri/renderD128`, `wayland-0`, XWayland `:0` |
| Default graphics | Mesa 25.0.7-2+deb13u1, llvmpipe LLVM 19.1.7, OpenGL 4.5, EGL 1.5, Vulkan loader 1.4.309 with llvmpipe device |
| Opt-in GL diagnostic | `GALLIUM_DRIVER=d3d12 LD_LIBRARY_PATH=/usr/lib/wsl/lib` exposed accelerated Radeon D3D12 and GL 4.6 in GLX |
| Rendering dependencies | GTK 4.18.6, libepoxy 1.5.10, Debian mpv/libmpv 0.40.0-3+deb13u1 (client API 2.5.0), FFmpeg 7.1.5-0+deb13u1, libplacebo 7.349.0 |
| Toolchain | GCC 14.2.0, Vala 0.56.18, Meson 1.7.0, Ninja 1.12.1 |

The default Mesa EGL implementation advertised `EGL_EXT_pixel_format_float`.
That is an EGL capability advertisement. It does not establish the bit depth
or transfer function of WSLg's presentation surface.

## Builds and checks

```sh
# Run apt-get as root in Debian
apt-get install -y mesa-utils vulkan-tools wayland-utils mpv
glxinfo -B
eglinfo -B
vulkaninfo --summary
wayland-info
GALLIUM_DRIVER=d3d12 LD_LIBRARY_PATH=/usr/lib/wsl/lib glxinfo -B

meson setup /var/tmp/majoris-wsl-standard -Dintrospection=enabled
ninja -C /var/tmp/majoris-wsl-standard
GDK_BACKEND=wayland GIO_USE_VFS=local meson test -C /var/tmp/majoris-wsl-standard --print-errorlogs

PKG_CONFIG_PATH=/var/tmp/majoris-audit-mpv/install/lib/x86_64-linux-gnu/pkgconfig \
  meson setup /var/tmp/majoris-wsl-experimental -Dintrospection=enabled \
  -Dexperimental_embedded_gpu_next=true -Dexperimental_gtk_pq=true
ninja -C /var/tmp/majoris-wsl-experimental
LD_LIBRARY_PATH=/var/tmp/majoris-audit-mpv/install/lib/x86_64-linux-gnu \
  GDK_BACKEND=wayland GIO_USE_VFS=local \
  meson test -C /var/tmp/majoris-wsl-experimental --print-errorlogs
```

The standard build passed 13/13 tests and the opt-in build passed 14/14.
Both builds included the C components, demo, and introspection. The patched
libmpv was the isolated build of mpv PR #16818 at
`80351bb32492402c894bb4291acdd44594db8450`. The project still reports missing
`MPV_RENDER_PARAM_BACKEND` when stock headers are used with the opt-in.
Clean build logs contained 530 standard and 539 experimental warnings in
Vala-generated C. The zero-warning gate remains open.
The source-structure checker also passed on Windows after normalizing
repository-relative paths to Meson's slash-separated spelling.

## Playback and measurements

The local probe in `build-wsl-qualification/` creates a real GTK window and
MediaKit session, opens media through the public API, requests a resize and a
seek, and closes the session and window. It records frame submission and
decoder selection. Run it with `LC_NUMERIC=C bash build-wsl-qualification/run.sh`
for the default Mesa path. The first runs with the inherited
`en_US.UTF-8` numeric locale failed before loading media. Setting
`LC_NUMERIC=C` restored standard playback. The shipped demo now keeps GTK's
UI locale while setting the numeric category to C before GTK starts, as
required by the libmpv client API. GTK hosts embedding MediaKit must preserve
that same libmpv requirement.

The following default-Mesa measurements are single-run process totals from
`/usr/bin/time -v`, including startup, seek, resize, and teardown. CPU values
above 100% indicate use of multiple cores. The generated patterns are 30 fps,
five seconds long. The initial HEVC encode lost its primaries and transfer
tags. Those first measurements describe 10-bit HEVC performance only.

| Standard MediaView input | Frame submitted | Decoder | CPU | Peak RSS |
| --- | --- | --- | ---: | ---: |
| Repository multistream SDR | Yes | Software | 33% | 282,568 KiB |
| Repository 64×64 Main10 PQ | Yes | Software | 16% | 302,764 KiB |
| 1080p Rec.709 H.264 | Yes | NVDEC copy-back | 525% | 449,712 KiB |
| 4K HEVC Main10, initial untagged encode | Yes | NVDEC copy-back | 930% | 734,944 KiB |
| 1080p HEVC Main10, initial untagged encode | Yes | NVDEC copy-back | 559% | 462,952 KiB |

The standard view reports an SDR output target. No numerical tone-mapping
comparison or physical output measurement was performed.
The default software GL path rejected patched gpu-next context creation
before PQ texture submission. The native HDR format and storage budget
tests passed as standalone contracts.

Under the process-local D3D12 override, GTK initially created an OpenGL ES
context and the native frame bridge rejected it. `HdrMediaView` now requests
desktop OpenGL 3.2 before realizing its context. After that change both
view probes submitted frames on all five inputs and exited successfully.
The HEVC files were remuxed with the `hevc_metadata` bitstream filter and
`ffprobe` confirmed BT.2020 primaries and SMPTE ST 2084 or ARIB STD-B67 transfer
respectively before the retest.

```sh
GALLIUM_DRIVER=d3d12 LD_LIBRARY_PATH=/usr/lib/wsl/lib LC_NUMERIC=C \
  RUN_PREFIX=verified- bash build-wsl-qualification/run.sh
```

| Source | Standard CPU / peak RSS | Experimental CPU / peak RSS |
| --- | ---: | ---: |
| 1080p Rec.709, 30 fps | 22% / 418,416 KiB | 25% / 471,564 KiB |
| 4K BT.2020/PQ Main10, 30 fps | 36% / 573,280 KiB | 36% / 627,368 KiB |
| 1080p BT.2020/HLG Main10, 30 fps | 25% / 450,976 KiB | 29% / 486,284 KiB |

Both views reported NVDEC copy-back on those three files. Rates in the table
are source rates. Presented frame rate, dropped frames, and GPU utilization
were not measured. Successful PQ submission exercises the native checks
for framebuffer completeness and actual RGBA16F storage, the synchronization
and ownership handoff, and GTK's retained BT.2100/PQ color state. It does not
sample output pixels or establish display precision. The frame bridge has no
explicit CPU pixel readback. Driver and compositor transfers were not traced.
The harness requested resize and seek and closed each window, but it did
not assert mapped allocations, resource reclamation, or mid-open cancellation.
Core cancellation is covered separately by the Meson contract test.

Stock mpv's external Wayland/OpenGL gpu-next rejected default llvmpipe.
The direct CLI diagnostic with `--gpu-sw` reached end of file on the
repository SDR fixture. The D3D12 override selected Radeon and also reached
end of file, then exited with a segmentation fault. Both were direct CLI
diagnostics. The project launcher requires mpv 0.42 or later, and the
Meson launcher test exercises its IPC contract with the existing test double.

## Capability matrix

| Capability | Compiled | Runtime Tested | Native HDR Verified | Limitation |
| --- | --- | --- | --- | --- |
| Core, Gtk and standard OpenGL | Yes | SDR, PQ and HLG playback through SDR view | No | Default GL software; NVDEC copy-back observed on generated files |
| Patched embedded gpu-next and GTK PQ | Yes | RGBA16F BT.2100/PQ texture submitted with D3D12 override | No | Unsupported on default llvmpipe |
| External Wayland gpu-next | Launcher yes | IPC test double and direct stock mpv CLI | No | Stock launcher version unsupported; D3D12 CLI teardown crash |
| GTK to WSLg native HDR negotiation | Applicable | Wayland registry inspected | No | Unsupported through the advertised protocol set |
| HDR10+ dynamic metadata, Dolby Vision 5, 7 MEL, 7 FEL and 8 | Applicable | Not Tested | No | No qualified fixtures or reconstruction comparison |
| Native Windows reference player comparison | N/A | Not Tested | No | No matched reference playback |

Outstanding on native Majoris/GNOME are color-managed Wayland negotiation,
verified output color space and HDR scanout, reference pixel and tone-mapping
measurements, HDR10+ and Dolby Vision fixture coverage, FEL reconstruction
against a reference, and matched frame-rate, drop, utilization, and resource
measurements across repeated playback and teardown. This WSL run does not
establish zero-copy rendering, bounded driver allocations, or absence of
rendering glitches.

Diagnostic, playback, and performance logs are in
`/var/tmp/majoris-wsl-evidence` in Debian. The display snapshot is
`build-wsl-qualification/dxdiag.txt` on Windows.
