gtk = dependency('gtk4', version: '>=4.16')
gtk_resources = gnome.compile_resources(
  'majoris-media-gtk-resources',
  '../../data/media-kit-gtk.gresource.xml',
  source_dir: '../../data',
  c_name: 'media_kit_gtk',
)
gtk_sources = [
  'media-view.vala',
  'media-controls.vala',
  'gpu-next-controls.vala',
]
gtk_native_libraries = []
if experimental_gtk_pq
  gtk_sources += [
    'hdr-media-view.vala',
    '../../native/gtk/hdr-frame.vapi',
  ]
  gtk_native_libraries += static_library(
    'media-hdr-frame',
    '../../native/gtk/hdr-frame.c',
    '../../native/gtk/hdr-frame-budget.c',
    '../../native/gtk/hdr-frame-format.c',
    dependencies: [gtk, epoxy, dependency('threads')],
    pic: true,
  )
endif

gtk_library = shared_library(
  'majoris-media-gtk4',
  files(gtk_sources),
  gtk_resources,
  dependencies: [core_api, gtk],
  link_whole: gtk_native_libraries,
  include_directories: include_directories('../../native/gtk'),
  vala_args: ['--shared-library=libmajoris-media-gtk4.so.0', '--hide-internal'],
  version: meson.project_version(),
  soversion: '0',
  install: true,
  vala_header: 'majoris-media-gtk4.h',
  vala_vapi: 'majoris-media-gtk4-1.vapi',
  vala_gir: 'MediaKitGtk-1.0.gir',
  install_dir: [
    get_option('libdir'),
    get_option('includedir') / 'majoris-media-gtk4-1',
    get_option('datadir') / 'vala/vapi',
    get_option('datadir') / 'gir-1.0',
  ],
)
gtk_api = declare_dependency(
  link_with: gtk_library,
  dependencies: [core_api, gtk],
  include_directories: include_directories('.'),
)

if gir_compiler.found()
  gtk_typelib = custom_target(
    'MediaKitGtk typelib',
    output: 'MediaKitGtk-1.0.typelib',
    command: [
      gir_compiler,
      '--includedir=' + core_gir_dir,
      '-o', '@OUTPUT@',
      meson.current_build_dir() / 'MediaKitGtk-1.0.gir',
    ],
    depends: [gtk_library, core_typelib],
    install: true,
    install_dir: get_option('libdir') / 'girepository-1.0',
  )
endif

pkg.generate(
  gtk_library,
  filebase: 'majoris-media-gtk4-1',
  name: 'Majoris Media GTK4',
  description: 'Reusable GTK4 media view and controls (OpenGL video output and interactive transport)',
  subdirs: 'majoris-media-gtk4-1',
  requires: ['majoris-media-1', 'gtk4'],
)
install_data('majoris-media-gtk4-1.deps', install_dir: get_option('datadir') / 'vala/vapi')
