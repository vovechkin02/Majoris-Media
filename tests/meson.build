python3 = find_program('python3')

test(
  'media-source-documentation',
  python3,
  args: [meson.project_source_root() / 'tools/check_source_docs.py'],
  suite: 'unit',
)
test(
  'media-source-structure',
  python3,
  args: [meson.project_source_root() / 'tools/check_structure.py'],
  suite: 'unit',
)

core_test = executable(
  'test-core-contract',
  'unit/core-contract.vala',
  dependencies: [core_api],
)
test('media-core-contract', core_test, suite: 'unit')

if get_option('gtk')
  gtk_test = executable(
    'test-gtk-contract',
    'integration/gtk-contract.vala',
    dependencies: [gtk_api],
  )
  test(
    'media-gtk-contract',
    gtk_test,
    suite: 'integration',
    env: ['GDK_BACKEND=headless'],
    timeout: 30,
  )
endif

if mpv.found()
  metadata_test = executable(
    'test-engine-metadata',
    'integration/engine-metadata.vala',
    dependencies: [core_api],
  )
  test(
    'media-engine-metadata',
    metadata_test,
    args: [meson.current_source_dir() / 'fixtures/multi-stream.mkv'],
    suite: 'integration',
    timeout: 15,
  )

  playback_test = executable(
    'test-engine-playback',
    'integration/engine-playback.vala',
    dependencies: [core_api],
  )
  test(
    'media-engine-playback',
    playback_test,
    args: [meson.current_source_dir() / 'fixtures/short-tone.wav'],
    suite: 'integration',
    timeout: 15,
  )
endif

if mpv.found()
  transport_test = executable(
    'test-engine-transport',
    'integration/engine-transport.vala',
    dependencies: [core_api],
  )
  test(
    'media-engine-standalone-m2ts',
    transport_test,
    args: [meson.current_source_dir() / 'fixtures/standalone-reference.m2ts'],
    suite: 'integration',
    timeout: 15,
  )
endif

if mpv.found()
  audio_test = executable(
    'test-engine-audio',
    'integration/engine-audio.vala',
    dependencies: [core_api],
  )
  test(
    'media-engine-flac-surround',
    audio_test,
    args: [meson.current_source_dir() / 'fixtures/surround-5.1.flac', 'flac'],
    suite: 'integration',
    timeout: 15,
  )
  test(
    'media-engine-eac3-surround',
    audio_test,
    args: [meson.current_source_dir() / 'fixtures/surround-eac3.eac3', 'eac3'],
    suite: 'integration',
    timeout: 15,
  )
endif
