project(
  'majoris-media',
  ['c', 'vala'],
  version: '0.1.0',
  license: 'GPL-3.0-or-later',
  meson_version: '>=1.4',
  default_options: ['c_std=gnu11', 'warning_level=2'],
)

pkg = import('pkgconfig')
gnome = import('gnome')

gio = dependency('gio-2.0', version: '>=2.76')
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
    'Example consumer': get_option('examples') and get_option('gtk'),
    'Introspection': gir_compiler.found(),
    'Tests': get_option('tests'),
    'Playback backend implemented': false,
  },
  section: 'Majoris Media Stage 1',
  bool_yn: true,
)
