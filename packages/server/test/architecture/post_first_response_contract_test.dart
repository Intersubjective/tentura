import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

/// The Post first-response receipt is declared in the updates event contract
/// (`docs/contracts/updates-event-contract.json`), in the server enum, and has
/// a producer and a classification matching plan §5.6.
const _eventType = 'postFirstResponse';
const _coveringTest =
    'packages/server/test/domain/use_case/post_first_response_pg_test.dart';

void main() {
  final contract =
      jsonDecode(_contractFile().readAsStringSync()) as Map<String, Object?>;

  test('AttentionEventType declares the Post first response', () {
    expect(
      AttentionEventType.values.map((e) => e.name),
      contains(_eventType),
    );
  });

  test('the contract lists the event type with its producer and test', () {
    final entries = (contract['eventTypes']! as List)
        .cast<Map<String, dynamic>>();
    final entry = entries.singleWhere(
      (e) => e['eventType'] == _eventType,
      orElse: () => throw TestFailure('$_eventType missing from eventTypes'),
    );

    expect(entry['producer'], contains('BeaconRoomCase.createMessage'));
    expect(entry['producer'], contains('BeaconRoomCase.reactionToggle'));
    expect(entry['coveringTest'], _coveringTest);
  });

  test('the room case is declared as a producer of the event', () {
    final producers = (contract['producers']! as List)
        .cast<Map<String, dynamic>>()
        .where((p) => p['eventType'] == _eventType)
        .toList();

    expect(producers, hasLength(1));
    expect(
      producers.single['useCase'],
      'packages/server/lib/domain/use_case/beacon_room_case.dart',
    );
    expect(producers.single['coveringTest'], _coveringTest);
  });

  test('the contract classifies the event as plan §5.6 declares', () {
    final classifications = (contract['eventClassifications']! as List)
        .cast<Map<String, dynamic>>()
        .where((e) => e['eventType'] == _eventType)
        .toList();
    expect(classifications, hasLength(1));
    expect(classifications.single['status'], 'supported');

    final variants = (classifications.single['variants']! as List)
        .cast<Map<String, dynamic>>();
    expect(variants, hasLength(1));
    final variant = variants.single;
    expect(variant['recipientPredicate'], 'reason:postAuthor');
    expect(variant['scope'], 'beacon');
    expect(variant['attentionClass'], 'optional');
    expect(variant['placement'], 'primary');
    expect(variant['groupKey'], 'beaconId');
    expect(variant['orderingEffect'], 'stable');
    expect(variant['accessPolicy'], 'beacon_content');
    expect(variant['recoverableVia'], 'room');
    expect(variant['clearPolicy'], 'explicit_or_request_open');
    expect(variant['coalescible'], isTrue);
    expect(variant['selfAuthored'], isFalse);
    expect(variant['producerTests'], [_coveringTest]);
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
