import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

/// A17: the closure receipts are declared in the updates event contract
/// (`docs/contracts/updates-event-contract.json`) and in the server enum.
const _closureEventTypes = {
  'closureOpened',
  'closureDraftReminder',
  'closureFinalized',
  'closureCancelled',
  'requestStale',
};

void main() {
  final contract =
      jsonDecode(_contractFile().readAsStringSync()) as Map<String, Object?>;

  test('AttentionEventType declares the closure receipt types', () {
    final names = AttentionEventType.values.map((e) => e.name).toSet();
    expect(names, containsAll(_closureEventTypes));
  });

  test('the contract lists every closure event type with a producer', () {
    final entries = (contract['eventTypes']! as List).cast<Map<String, dynamic>>();
    final byType = {for (final e in entries) e['eventType']: e};
    for (final type in _closureEventTypes) {
      expect(byType, contains(type), reason: '$type missing from eventTypes');
      expect(byType[type]!['producer'], isNotEmpty);
      expect(byType[type]!['coveringTest'], isNotEmpty);
    }
  });

  test('the contract classifies every closure event type', () {
    final classified = (contract['eventClassifications']! as List)
        .cast<Map<String, dynamic>>()
        .map((e) => e['eventType'])
        .toSet();
    expect(classified, containsAll(_closureEventTypes));
  });

  test('the two sweeps are declared as producers', () {
    final producers = jsonEncode(contract['producers']);
    expect(producers, contains('closure_draft_reminder_sweep_case.dart'));
    expect(producers, contains('stale_request_reminder_sweep_case.dart'));
  });
}

File _contractFile() {
  for (final path in const [
    '../../docs/contracts/updates-event-contract.json',
    'docs/contracts/updates-event-contract.json',
  ]) {
    final f = File(path);
    if (f.existsSync()) return f;
  }
  throw StateError('Updates event contract not found');
}
