import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared attention domain does not depend on data or UI', () {
    final attentionDomain = Directory('lib/domain/attention');
    final sourceFiles = attentionDomain
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('.freezed.dart'));

    for (final file in sourceFiles) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('package:tentura/data/')),
        reason: file.path,
      );
      expect(source, isNot(contains('/data/')), reason: file.path);
      expect(source, isNot(contains('/ui/')), reason: file.path);
    }
  });
}
