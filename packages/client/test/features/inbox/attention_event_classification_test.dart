import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/attention_event_classification.dart';

/// The client mirror of `eventClassifications` is asserted against the real
/// contract file, exactly as the server mirrors `placement` in
/// `updates_event_contract_test.dart`. Values are never hand-copied into this
/// test: a contract edit that the client does not know about must fail here.
void main() {
  final contract = _loadContract();
  final classifications = (contract['eventClassifications']! as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList(growable: false);

  test('the client mirror knows exactly the contract\'s event types', () {
    final declared = {
      for (final entry in classifications) entry['eventType']! as String,
    };
    expect(
      attentionEventClassifications.keys.toSet(),
      declared,
      reason:
          'the card classification lookup must cover every declared event '
          'type and invent none',
    );
  });

  test('every declared variant agrees with the client mirror', () {
    var variantsChecked = 0;
    for (final entry in classifications) {
      final eventType = entry['eventType']! as String;
      final mirrored = attentionEventClassifications[eventType];
      expect(mirrored, isNotNull, reason: '$eventType is not mirrored');
      for (final raw in entry['variants']! as List) {
        final variant = Map<String, dynamic>.from(raw as Map);
        variantsChecked++;
        expect(
          mirrored!.headlineTreatment.name,
          variant['headlineTreatment'],
          reason: '$eventType ${variant['recipientPredicate']} headline',
        );
        expect(
          mirrored.coalescible,
          variant['coalescible'],
          reason: '$eventType ${variant['recipientPredicate']} coalescible',
        );
      }
    }
    // Guards the loop itself: an empty contract read would pass vacuously.
    expect(variantsChecked, greaterThanOrEqualTo(30));
  });

  test('an event type whose variants disagree cannot be mirrored by type', () {
    // The lookup is keyed by `eventType` alone. That is only legitimate while
    // every variant of a type declares the same card treatment; the moment the
    // contract splits one, this unit needs a discriminator and must not
    // silently answer with one variant's values.
    for (final entry in classifications) {
      final variants = (entry['variants']! as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      expect(
        variants.map((v) => v['headlineTreatment']).toSet(),
        hasLength(1),
        reason: '${entry['eventType']} variants disagree on headlineTreatment',
      );
      expect(
        variants.map((v) => v['coalescible']).toSet(),
        hasLength(1),
        reason: '${entry['eventType']} variants disagree on coalescible',
      );
    }
  });

  test('an unknown or missing event type takes the documented default', () {
    expect(classifyAttentionEvent(null), kUnknownAttentionEventClassification);
    expect(classifyAttentionEvent(''), kUnknownAttentionEventClassification);
    expect(
      classifyAttentionEvent('somethingTheServerAddedLater'),
      kUnknownAttentionEventClassification,
    );
    // Documented and explicitly written: never coalesce what we cannot read
    // (coalescing is the only lossy operation on the card), and headline it as
    // the Request it is grouped under.
    expect(kUnknownAttentionEventClassification.coalescible, isFalse);
    expect(
      kUnknownAttentionEventClassification.headlineTreatment,
      AttentionHeadlineTreatment.beacon,
    );
  });

  test('the event type is read from the receipt presentation payload', () {
    expect(
      attentionEventTypeOf('{"eventType":"relayReceived","beaconId":"b1"}'),
      'relayReceived',
    );
    expect(attentionEventTypeOf('{}'), isNull);
    expect(attentionEventTypeOf('not json'), isNull);
    expect(attentionEventTypeOf(null), isNull);
    // A payload that carries one classifies through it end to end.
    expect(
      classifyAttentionEventPayload('{"eventType":"relayReceived"}').coalescible,
      isFalse,
    );
    expect(
      classifyAttentionEventPayload('{"eventType":"roomMessagePosted"}')
          .coalescible,
      isTrue,
    );
  });
}

Map<String, dynamic> _loadContract() => Map<String, dynamic>.from(
  jsonDecode(_contractFile().readAsStringSync()) as Map,
);

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
