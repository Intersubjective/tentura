import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tentura-2r7: `flutter build web --no-pub` trusts whatever gitignored
/// lib/app/di/di.config.dart happens to sit on disk. Commit a2b4d3a29
/// deleted my_work_desk_preferences_repository.dart and
/// my_work_desk_preferences_port.dart and dropped MyWorkCase's 12th
/// constructor argument (`_deskPreferences`), but a developer's stale,
/// un-regenerated di.config.dart from before that commit still imported
/// the deleted files and called MyWorkCase with 12 positional arguments,
/// so `flutter build web --no-pub` failed with "couldn't read" import
/// errors plus an argument-count mismatch.
///
/// The fixture below is not hand-written: it is the literal
/// injectable-generated di.config.dart captured by checking out
/// my_work_case.dart, my_work_desk_preferences_repository.dart and
/// my_work_desk_preferences_port.dart at commit
/// 7f4aeb550dab1b3e6808d5cb9ea794d2516805f2 (a2b4d3a29's parent) and
/// running `dart run build_runner build` against them, then restoring
/// the tree. It reproduces the bug byte-for-byte, down to the
/// MyWorkDeskPreferencesPort import landing on di.config.dart:225 as
/// cited in the bug report.
File _repoFile(String path) {
  for (final prefix in const ['../../', '']) {
    final file = File('$prefix$path');
    if (file.existsSync()) return file.absolute;
  }
  throw StateError('Repo file not found: $path');
}

Directory _repoRoot() =>
    _repoFile('packages/client/pubspec.yaml').parent.parent.parent;

void main() {
  test(
    'flutter build web --no-pub survives a stale, pre-a2b4d3a29 My Work DI config (tentura-2r7)',
    () {
      final repoRoot = _repoRoot();
      final clientRoot = Directory('${repoRoot.path}/packages/client');
      final diConfig = File(
        '${clientRoot.path}/lib/app/di/di.config.dart',
      );
      final staleFixture = _repoFile(
        'packages/client/test/architecture/fixtures/'
        'stale_my_work_di_config_tentura_2r7.dart.txt',
      ).readAsStringSync();

      // Sanity-check the fixture still represents the reported bug shape,
      // so this test cannot silently rot into a no-op if the fixture file
      // is ever edited.
      expect(
        staleFixture,
        contains('MyWorkDeskPreferencesPort'),
        reason:
            'Fixture must still call MyWorkCase with the deleted '
            'MyWorkDeskPreferencesPort argument',
      );
      expect(
        staleFixture,
        contains(
          "import 'package:tentura/features/my_work/data/repository/"
          "my_work_desk_preferences_repository.dart'",
        ),
        reason: 'Fixture must still import the deleted preferences repository',
      );

      final original = diConfig.existsSync()
          ? diConfig.readAsStringSync()
          : null;
      addTearDown(() {
        if (original != null) {
          diConfig.writeAsStringSync(original);
        } else if (diConfig.existsSync()) {
          diConfig.deleteSync();
        }
      });

      diConfig.createSync(recursive: true);
      diConfig.writeAsStringSync(staleFixture);

      final result = Process.runSync('flutter', [
        'build',
        'web',
        '--no-pub',
      ], workingDirectory: clientRoot.path);

      expect(
        result.exitCode,
        0,
        reason:
            '`flutter build web --no-pub` must succeed even when a stale '
            'gitignored di.config.dart references files deleted by '
            'a2b4d3a29 and calls MyWorkCase with its old 12-argument '
            'shape\nstdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
