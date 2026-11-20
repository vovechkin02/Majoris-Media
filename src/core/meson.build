core_sources = files(
  'audio-device.vala',
  'audio-information.vala',
  'audio-output-information.vala',
  'audio-policy.vala',
  'disc-title.vala',
  'media-capabilities.vala',
  'media-chapter.vala',
  'media-description.vala',
  'media-error.vala',
  'media-probe.vala',
  'media-session.vala',
  'media-source.vala',
  'media-track.vala',
  'open-gl-output.vala',
  'playback-options.vala',
  'playback-state.vala',
  'video-color-information.vala',
  'video-information.vala',
  'video-rendering-information.vala',
  'video-rendering-policy.vala',
  'playback/mpv-backend.vala',
  'playback/playback-backend.vala',
  'playback/unavailable-backend.vala',
  'rendering/gpu-next-capabilities.vala',
  'rendering/gpu-next-ipc.vala',
  'rendering/gpu-next-playback-status.vala',
  'rendering/gpu-next-launch-options.vala',
  'rendering/gpu-next-probe.vala',
  'rendering/gpu-next-window.vala',
  '../../native/playback/engine.vapi',
)

engine_dependencies = [gio]
engine_c_args = []
if mpv.found()
  engine_dependencies += [mpv, epoxy]
  engine_c_args += ['-DMEDIAKIT_HAVE_MPV']
  if experimental_embedded_gpu_next
    engine_c_args += ['-DMEDIAKIT_EXPERIMENTAL_EMBEDDED_GPU_NEXT']
  endif
endif

engine_adapter = static_library(
  'media-engine-adapter',
  '../../native/playback/engine-adapter.c',
  dependencies: engine_dependencies,
  c_args: engine_c_args,
  pic: true,
)

core_library = shared_library(
  'majoris-media',
  core_sources,
  dependencies: [gio, gio_unix, json_glib],
  link_whole: engine_adapter,
  include_directories: include_directories('../../native/playback'),
  vala_args: ['--shared-library=libmajoris-media.so.0', '--hide-internal'],
  version: meson.project_version(),
  soversion: '0',
  install: true,
  vala_header: 'majoris-media.h',
  vala_vapi: 'majoris-media-1.vapi',
  vala_gir: 'MediaKit-1.0.gir',
  install_dir: [
    get_option('libdir'),
    get_option('includedir') / 'majoris-media-1',
    get_option('datadir') / 'vala/vapi',
    get_option('datadir') / 'gir-1.0',
  ],
)
core_api = declare_dependency(
  link_with: core_library,
  dependencies: [gio, json_glib],
  include_directories: include_directories('.'),
)
core_gir_dir = meson.current_build_dir()

if gir_compiler.found()
  core_typelib = custom_target(
    'MediaKit typelib',
    output: 'MediaKit-1.0.typelib',
    command: [
      gir_compiler,
      '-o', '@OUTPUT@',
      core_gir_dir / 'MediaKit-1.0.gir',
    ],
    depends: core_library,
    install: true,
    install_dir: get_option('libdir') / 'girepository-1.0',
  )
endif

pkg.generate(
  core_library,
  filebase: 'majoris-media-1',
  name: 'Majoris Media Core',
  description: 'Reusable headless media API with asynchronous libmpv playback',
  subdirs: 'majoris-media-1',
  requires: ['gio-2.0', 'json-glib-1.0'],
)
install_data('majoris-media-1.deps', install_dir: get_option('datadir') / 'vala/vapi')
