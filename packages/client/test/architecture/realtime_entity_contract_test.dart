import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

void main() {
  test('realtime manifest covers the closed client protocol and evidence', () {
    final contractFile = _contractFile();
    final contract = jsonDecode(contractFile.readAsStringSync()) as Map;
    final entries = (contract['kinds']! as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);
    final repoRoot = contractFile.parent.parent.parent;

    expect(contract['schemaVersion'], 1);
    expect(contract['channel'], 'entity_changes');
    expect(entries, isNotEmpty);

    final canonicalWireKinds = <String>{};
    final clientKinds = <String>{};
    final acceptedWireKinds = <String>{};
    for (final entry in entries) {
      final wireKind = entry['wireKind']! as String;
      final clientKindName = entry['clientKind']! as String;
      final accepted = (entry['acceptedWireKinds']! as List).cast<String>();
      final triggerArgs = (entry['genericTriggerArgs']! as List).cast<String>();
      final publishers = (entry['specializedPublishers']! as List)
          .cast<String>();
      final impacts = (entry['impacts']! as List).cast<String>();
      final tests = (entry['tests']! as List).cast<String>();

      expect(canonicalWireKinds.add(wireKind), isTrue, reason: wireKind);
      expect(clientKinds.add(clientKindName), isTrue, reason: clientKindName);
      expect(accepted, contains(wireKind), reason: wireKind);
      expect(
        triggerArgs.isNotEmpty || publishers.isNotEmpty,
        isTrue,
        reason: '$wireKind has no server mapping',
      );
      expect(impacts, isNotEmpty, reason: '$wireKind has no impact mapping');
      expect(tests, isNotEmpty, reason: '$wireKind has no test evidence');

      final clientKind = RealtimeEntityKind.values.singleWhere(
        (kind) => kind.name == clientKindName,
      );
      for (final acceptedWireKind in accepted) {
        expect(
          acceptedWireKinds.add(acceptedWireKind),
          isTrue,
          reason: 'duplicate wire alias $acceptedWireKind',
        );
        expect(
          RealtimeEntityKind.fromWire(acceptedWireKind),
          clientKind,
          reason: acceptedWireKind,
        );
      }
      for (final path in tests) {
        expect(
          File.fromUri(repoRoot.uri.resolve(path)).existsSync(),
          isTrue,
          reason: '$wireKind evidence is missing: $path',
        );
      }
    }

    expect(
      clientKinds,
      RealtimeEntityKind.values.map((kind) => kind.name).toSet(),
    );
    expect(RealtimeEntityKind.fromWire('unknown_kind'), isNull);

    final notification = entries.singleWhere(
      (entry) => entry['wireKind'] == 'notification',
    );
    expect(
      (notification['impacts']! as List).cast<String>(),
      containsAll(const ['updates_feed', 'updates_badge']),
    );

    final contractTests = (contract['contractTests']! as List).cast<String>();
    expect(
      contractTests.any((path) => path.startsWith('packages/client/test/')),
      isTrue,
    );
    expect(
      contractTests.any((path) => path.startsWith('packages/server/test/')),
      isTrue,
    );
    for (final path in contractTests) {
      expect(
        File.fromUri(repoRoot.uri.resolve(path)).existsSync(),
        isTrue,
        reason: 'contract test is missing: $path',
      );
    }
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
