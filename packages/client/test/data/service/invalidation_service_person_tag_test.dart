import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

Map<String, dynamic> _personTagFrame({
  required String ownerId,
  Object? revision,
  String event = 'update',
}) => {
  'type': 'subscription',
  'path': 'entity_changes',
  'payload': {
    'entity': 'person_tag',
    'id': ownerId,
    'event': event,
    'actor_user_id': ownerId,
    'revision': ?revision,
  },
};

List<RealtimeEntityChange> _deliver(Map<String, dynamic> frame) {
  final received = <RealtimeEntityChange>[];
  fakeAsync((async) {
    final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
    final service = InvalidationService.forTesting(wsMessages.stream);
    final sub = service.entityChanges.listen(received.add);

    wsMessages.add(frame);
    async.elapse(const Duration(milliseconds: 100));

    unawaited(sub.cancel());
    unawaited(service.dispose());
    unawaited(wsMessages.close());
  });
  return received;
}

void main() {
  group('person_tag realtime kind', () {
    const ownerId = 'Uowner0000001';

    test('the wire name person_tag parses to RealtimeEntityKind.personTag', () {
      expect(
        RealtimeEntityKind.fromWire('person_tag'),
        RealtimeEntityKind.personTag,
      );
    });

    test('a frame with a decimal revision yields a personTag change carrying '
        'that revision', () {
      final received = _deliver(
        _personTagFrame(ownerId: ownerId, revision: '42'),
      );

      expect(received, hasLength(1));
      final change = received.single;
      expect(change.kind, RealtimeEntityKind.personTag);
      expect(change.aggregateId, ownerId);
      expect(change.operation, RealtimeOperation.update);
      expect(change.source, RealtimeChangeSource.serverInvalidation);
      expect(change.revision, BigInt.from(42));
    });

    test('a revision beyond 64 bits survives as a BigInt', () {
      final received = _deliver(
        _personTagFrame(
          ownerId: ownerId,
          revision: '9223372036854775808',
        ),
      );

      expect(received.single.revision, BigInt.parse('9223372036854775808'));
    });

    test('a non-numeric revision still invalidates, with no revision', () {
      final received = _deliver(
        _personTagFrame(ownerId: ownerId, revision: 'abc'),
      );

      expect(received, hasLength(1));
      expect(received.single.kind, RealtimeEntityKind.personTag);
      expect(received.single.aggregateId, ownerId);
      expect(received.single.revision, isNull);
    });

    test('a frame without a revision still invalidates, with no revision', () {
      final received = _deliver(_personTagFrame(ownerId: ownerId));

      expect(received, hasLength(1));
      expect(received.single.kind, RealtimeEntityKind.personTag);
      expect(received.single.revision, isNull);
    });

    test('the manifest maps wire kind person_tag to the personTag client kind, '
        'its server publisher, an impact and the parse evidence', () {
      final contract =
          jsonDecode(_contractFile().readAsStringSync()) as Map<String, dynamic>;
      final entry = (contract['kinds']! as List)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (kind) => kind['wireKind'] == 'person_tag',
            orElse: () => <String, dynamic>{},
          );

      expect(entry, isNotEmpty, reason: 'person_tag missing from the manifest');
      expect(entry['clientKind'], 'personTag');
      expect(entry['acceptedWireKinds'], ['person_tag']);
      expect(entry['specializedPublishers'], ['notify_person_tag_change']);
      expect(entry['impacts'], contains('people_tags'));
      expect(
        entry['tests'],
        contains(
          'packages/client/test/data/service/'
          'invalidation_service_person_tag_test.dart',
        ),
      );
    });
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
