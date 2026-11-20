core_sources = files(
  'audio-device.vala',
  'audio-information.vala',
  'audio-output-information.vala',
  'audio-policy.vala',
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
  'video-information.vala',
  'video-color-information.vala',
  'playback/mpv-backend.vala',
  'playback/playback-backend.vala',
  'playback/unavailable-backend.vala',
  '../../native/playback/engine-adapter.c',
  '../../native/playback/engine.vapi',
)

core_dependencies = [gio]
core_c_args = []
if mpv.found()
  core_dependencies += [mpv, epoxy]
  core_c_args += ['-DMEDIAKIT_HAVE_MPV']
endif

core_library = shared_library(
  'majoris-media',
  core_sources,
  dependencies: core_dependencies,
  c_args: core_c_args,
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
  dependencies: [gio],
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
  requires: ['gio-2.0'],
)
install_data('majoris-media-1.deps', install_dir: get_option('datadir') / 'vala/vapi')
