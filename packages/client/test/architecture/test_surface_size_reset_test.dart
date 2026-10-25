@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #754: CI runs many test files in one isolate (scripts/gen_test_bundles.py).
/// A test-surface size set with `binding.setSurfaceSize(size)` outlives the
/// test that set it, and the bundle's between-files reset cannot put it back
/// (`setSurfaceSize` only works inside a test). A file that sets it and never
/// resets it moves every later file onto its surface: the 360 x 400 inbox
/// viewport of `activity_live_motion_test.dart` became 1200 x 900 behind
/// `constellation_text_view_test.dart`.
///
/// So every test file that sets a surface size also resets it, the way the
/// flutter_test docs show:
/// `addTearDown(() => tester.binding.setSurfaceSize(null))`.
final _setSize = RegExp(r'setSurfaceSize\(\s*(?!null\s*\))');
final _reset = RegExp(r'addTearDown\([^;]*setSurfaceSize\(\s*null\s*\)');

Directory _testRoot() => Directory('test').existsSync()
    ? Directory('test')
    : Directory('packages/client/test');

/// Whether [source] sets a surface size without a matching reset.
bool leaksSurfaceSize(String source) {
  final code = source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
  return _setSize.hasMatch(code) && !_reset.hasMatch(code);
}

void main() {
  test('the check tells a leaking file from a resetting one', () {
    expect(
      leaksSurfaceSize(
        'await tester.binding.setSurfaceSize(const Size(1200, 900));',
      ),
      isTrue,
    );
    expect(
      leaksSurfaceSize(
        'await tester.binding.setSurfaceSize(size);\n'
        'addTearDown(() => tester.binding.setSurfaceSize(null));',
      ),
      isFalse,
    );
    expect(leaksSurfaceSize('// setSurfaceSize(const Size(1, 1))'), isFalse);
  });

  test('every test file that sets a surface size resets it', () {
    final root = _testRoot();
    final prefix = root.path.substring(0, root.path.length - 'test'.length);
    final offenders = <String>[
      for (final entity in root.listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.contains(
              '${Platform.pathSeparator}_bundle'
              '${Platform.pathSeparator}',
            ) &&
            leaksSurfaceSize(entity.readAsStringSync()))
          entity.path.substring(prefix.length),
    ];
    expect(
      offenders..sort(),
      isEmpty,
      reason:
          'a surface size set without '
          'addTearDown(() => tester.binding.setSurfaceSize(null)) leaks into '
          'the next file of a CI bundle',
    );
  });
}
