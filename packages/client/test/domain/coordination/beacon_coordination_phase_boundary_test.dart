import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new coordination phase domain files do not import flutter or features', () {
    final violations = <String>[];

    final files = <File>[
      File('lib/domain/entity/beacon_coordination_phase.dart'),
      File('lib/domain/entity/open_blocker_cue.dart'),
    ];

    final coordinationDir = Directory('lib/domain/coordination');
    if (coordinationDir.existsSync()) {
      for (final child in coordinationDir.listSync(recursive: true)) {
        if (child is File && child.path.endsWith('.dart')) {
          files.add(child);
        }
      }
    }

    for (final file in files) {
      if (!file.existsSync()) continue;
      _checkFile(file, violations);
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}

void _checkFile(File entity, List<String> violations) {
  final content = entity.readAsStringSync();
  final rel = entity.path.replaceFirst('lib/', 'package:tentura/');
  if (content.contains("import 'package:flutter")) {
    violations.add('$rel: imports flutter');
  }
  if (content.contains('package:tentura/features/')) {
    violations.add('$rel: imports features');
  }
  if (content.contains('package:tentura/ui/')) {
    violations.add('$rel: imports ui');
  }
  if (content.contains('design_system')) {
    violations.add('$rel: imports design_system');
  }
}
