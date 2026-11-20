project(
  'majoris-media',
  ['c', 'vala'],
  version: '0.7.2',
  license: 'GPL-3.0-or-later',
  meson_version: '>=1.4',
  default_options: ['c_std=gnu11', 'warning_level=2'],
)

pkg = import('pkgconfig')
gnome = import('gnome')

gio = dependency('gio-2.0', version: '>=2.76')
json_glib = dependency('json-glib-1.0', version: '>=1.6')
mpv = dependency('mpv', required: get_option('mpv'))
epoxy = dependency('epoxy', required: mpv.found())
gir_compiler = find_program(
  'gi-compile-repository',
  'g-ir-compiler',
  required: get_option('introspection'),
)

subdir('src/core')

if get_option('gtk')
  subdir('src/gtk')
endif

if get_option('examples') and get_option('gtk')
  subdir('examples')
endif

if get_option('tests')
  subdir('tests')
endif

summary(
  {
    'Headless core': true,
    'GTK4 widget': get_option('gtk'),
    'libmpv playback enabled': mpv.found(),
    'Embedded OpenGL enabled': mpv.found() and get_option('gtk'),
    'Native HDR embedding verified': false,
    'Embedded gpu-next available': false,
    'Standalone gpu-next Wayland launcher': true,
    'Private IPC playback controller': true,
    'GTK external playback controls': get_option('gtk'),
    'Example consumer': get_option('examples') and get_option('gtk'),
    'Introspection': gir_compiler.found(),
    'Tests': get_option('tests'),
  },
  section: 'Majoris Media Stage 7 native HDR candidate',
  bool_yn: true,
)
