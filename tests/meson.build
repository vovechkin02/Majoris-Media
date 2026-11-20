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
