import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

void main() {
  test('coordination item use cases are declared in the updates producer contract', () {
    final contractFile = _contractFile();
    final contract = jsonDecode(contractFile.readAsStringSync()) as Map;
    final repoRoot = contractFile.parent.parent.parent;

    final producers = (contract['producers']! as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);

    final coordinationItemDir = Directory.fromUri(
      repoRoot.uri.resolve(
        'packages/server/lib/domain/use_case/coordination_item/',
      ),
    );
    final casePaths = coordinationItemDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('_case.dart'))
        .map(
          (file) =>
              'packages/server/lib/domain/use_case/coordination_item/'
              '${file.uri.pathSegments.last}',
        )
        .toSet();

    for (final casePath in casePaths) {
      final matches = producers.where((entry) => entry['useCase'] == casePath);
      expect(
        matches.length,
        1,
        reason:
            'coordination_item case must appear exactly once in producers: '
            '$casePath',
      );
    }

    for (final producer in producers) {
      final useCase = producer['useCase']! as String;
      final silent = producer['silent'] as bool? ?? false;

      if (silent) {
        final silentReason = (producer['silentReason'] as String?)?.trim() ?? '';
        final gap = (producer['gap'] as String?)?.trim() ?? '';
        expect(
          silentReason.isNotEmpty || gap.isNotEmpty,
          isTrue,
          reason: '$useCase silent entry needs silentReason or gap',
        );
        continue;
      }

      final eventTypeName = producer['eventType'] as String?;
      expect(
        eventTypeName,
        isNotNull,
        reason: '$useCase non-silent entry missing eventType',
      );
      expect(
        AttentionEventType.values.map((event) => event.name),
        contains(eventTypeName),
        reason: '$useCase names unknown AttentionEventType $eventTypeName',
      );

      final coveringTest = producer['coveringTest'] as String?;
      expect(
        coveringTest,
        isNotNull,
        reason: '$useCase non-silent entry missing coveringTest',
      );
      final coveringTestFile = File.fromUri(repoRoot.uri.resolve(coveringTest!));
      expect(
        coveringTestFile.existsSync(),
        isTrue,
        reason:
            '$useCase covering test does not exist: ${coveringTestFile.path}',
      );
    }
  });
}

File _contractFile() {
  for (final path in const [
    '../../docs/contracts/updates-event-contract.json',
    'docs/contracts/updates-event-contract.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file.absolute;
  }
  throw StateError('Updates event contract not found');
}
