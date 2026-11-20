project(
  'majoris-media',
  ['c', 'vala'],
  version: '0.7.7',
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
experimental_embedded_gpu_next = get_option('experimental_embedded_gpu_next')
if experimental_embedded_gpu_next
  if not mpv.found()
    error('Experimental embedded gpu-next requires a patched libmpv dependency')
  endif
  cc = meson.get_compiler('c')
  if not cc.has_header_symbol('mpv/render.h', 'MPV_RENDER_PARAM_BACKEND', dependencies: mpv)
    error('The selected libmpv headers lack the experimental MPV_RENDER_PARAM_BACKEND API')
  endif
endif
experimental_gtk_pq = get_option('experimental_gtk_pq')
if experimental_gtk_pq
  if not get_option('gtk') or not experimental_embedded_gpu_next
    error('Experimental GTK PQ requires GTK4 and the patched embedded gpu-next API')
  endif
  if not mpv.found()
    error('Experimental GTK PQ requires a libmpv build')
  endif
endif
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
    'Experimental embedded gpu-next compiled': experimental_embedded_gpu_next,
    'Standalone gpu-next Wayland launcher': true,
    'Native HDR display qualification': false,
    'Experimental color-tagged GTK PQ': experimental_gtk_pq,
    'Private IPC playback controller': true,
    'GTK external playback controls': get_option('gtk'),
    'Example consumer': get_option('examples') and get_option('gtk'),
    'Introspection': gir_compiler.found(),
    'Tests': get_option('tests'),
  },
  section: 'Majoris Media 0.7.7 GL storage and state integrity',
  bool_yn: true,
)
