import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('realtime manifest maps every kind to a live server publisher', () {
    final contractFile = _contractFile();
    final contract = jsonDecode(contractFile.readAsStringSync()) as Map;
    final entries = (contract['kinds']! as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);
    final repoRoot = contractFile.parent.parent.parent;
    final migration = File.fromUri(
      repoRoot.uri.resolve(
        'packages/server/lib/data/database/migration/m0114.dart',
      ),
    ).readAsStringSync();

    final triggerArgs = <String>{};
    final specializedPublishers = <String>{};
    for (final entry in entries) {
      final wireKind = entry['wireKind']! as String;
      final entryTriggerArgs = (entry['genericTriggerArgs']! as List)
          .cast<String>();
      final entryPublishers = (entry['specializedPublishers']! as List)
          .cast<String>();
      expect(
        entryTriggerArgs.isNotEmpty || entryPublishers.isNotEmpty,
        isTrue,
        reason: '$wireKind has no server producer',
      );
      for (final triggerArg in entryTriggerArgs) {
        expect(triggerArgs.add(triggerArg), isTrue, reason: triggerArg);
        expect(
          migration,
          contains("'$triggerArg'"),
          reason: '$wireKind trigger argument is absent from m0114',
        );
      }
      for (final publisher in entryPublishers) {
        expect(
          specializedPublishers.add(publisher),
          isTrue,
          reason: publisher,
        );
        expect(
          migration,
          contains('FUNCTION public.$publisher'),
          reason: '$wireKind publisher is absent from m0114',
        );
      }
    }

    expect(triggerArgs, isNotEmpty);
    expect(specializedPublishers, isNotEmpty);
    expect(
      specializedPublishers,
      {
        'notify_coordination_change',
        'notify_help_offer_admission_event_change',
        'notify_relationship_change',
      },
    );
  });
}

File _contractFile() {
  for (final path in const [
    '../../docs/contracts/realtime-entity-contract.json',
    'docs/contracts/realtime-entity-contract.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file.absolute;
  }
  throw StateError('Realtime entity contract manifest not found');
}
