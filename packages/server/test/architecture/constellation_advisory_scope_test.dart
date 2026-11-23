import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('constellation writes have no separate anchor advisory key', () {
    final sources = Directory('lib').listSync(recursive: true);
    final generated = RegExp(r'\.(g|freezed|gr|config|schema)\.dart$|/_g/');
    final retiredKey = RegExp(r'\bconstellation_anchor_apply\b');
    final references = <String>[];
    for (final source in sources.whereType<File>()) {
      if (!source.path.endsWith('.dart') || generated.hasMatch(source.path)) {
        continue;
      }
      for (final (index, line) in source.readAsLinesSync().indexed) {
        if (retiredKey.hasMatch(line)) {
          references.add('${source.path}:${index + 1}');
        }
      }
    }
    expect(references, isEmpty);
  });
}
