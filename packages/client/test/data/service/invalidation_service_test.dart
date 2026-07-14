import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';

Map<String, dynamic> _entityChange({
  required String entity,
  required String id,
  String event = 'update',
  String? actorUserId,
}) => {
  'type': 'subscription',
  'path': 'entity_changes',
  'payload': {
    'entity': entity,
    'id': id,
    'event': event,
    'actor_user_id': ?actorUserId,
  },
};

void main() {
  group('InvalidationService', () {
    test('ignores non-entity_changes websocket frames', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <String>[];
        final sub = service.beaconInvalidations.listen(received.add);

        wsMessages.add({'type': 'pong'});
        wsMessages.add({
          'type': 'subscription',
          'path': 'other',
          'payload': {'entity': 'beacon', 'id': 'b1'},
        });
        async.elapse(const Duration(milliseconds: 600));
        expect(received, isEmpty);

        unawaited(sub.cancel());
      });
    });

    test('duplicate beacon ids in debounce window emit once', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <String>[];
        final sub = service.beaconInvalidations.listen(received.add);

        for (var i = 0; i < 5; i++) {
          wsMessages.add(_entityChange(entity: 'beacon', id: 'beacon-1'));
        }
        async.elapse(const Duration(milliseconds: 100));
        expect(received, isEmpty);

        async.elapse(const Duration(milliseconds: 500));
        expect(received, ['beacon-1']);

        unawaited(sub.cancel());
      });
    });

    test('different beacon ids in same window are all emitted', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <String>[];
        final sub = service.beaconInvalidations.listen(received.add);

        wsMessages.add(_entityChange(entity: 'beacon', id: 'beacon-a'));
        wsMessages.add(_entityChange(entity: 'beacon', id: 'beacon-b'));
        wsMessages.add(_entityChange(entity: 'beacon', id: 'beacon-a'));
        async.elapse(const Duration(milliseconds: 500));

        expect(received.toSet(), {'beacon-a', 'beacon-b'});

        unawaited(sub.cancel());
      });
    });

    test('routes entity types to the matching debounced stream', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final forwards = <String>[];
        final helpOffers = <String>[];
        final capabilities = <String>[];

        final forwardSub = service.forwardInvalidations.listen(forwards.add);
        final helpSub = service.helpOfferInvalidations.listen(helpOffers.add);
        final capSub = service.capabilityInvalidations.listen(capabilities.add);

        wsMessages.add(_entityChange(entity: 'forward', id: 'f1'));
        wsMessages.add(_entityChange(entity: 'help_offer', id: 'h1'));
        wsMessages.add(
          _entityChange(entity: 'person_capability_event', id: 'u1'),
        );
        async.elapse(const Duration(milliseconds: 500));

        expect(forwards, ['f1']);
        expect(helpOffers, ['h1']);
        expect(capabilities, ['u1']);

        unawaited(forwardSub.cancel());
        unawaited(helpSub.cancel());
        unawaited(capSub.cancel());
      });
    });

    test('maps every supported kind into the closed domain contract', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);
        const wireKinds = <String, RealtimeEntityKind>{
          'beacon': RealtimeEntityKind.beacon,
          'forward': RealtimeEntityKind.forward,
          'help_offer': RealtimeEntityKind.helpOffer,
          'inbox_item': RealtimeEntityKind.inboxItem,
          'room_message': RealtimeEntityKind.roomMessage,
          'room_reaction': RealtimeEntityKind.roomReaction,
          'room_poll': RealtimeEntityKind.roomPoll,
          'participant': RealtimeEntityKind.participant,
          'fact_card': RealtimeEntityKind.factCard,
          'blocker': RealtimeEntityKind.blocker,
          'activity_event': RealtimeEntityKind.activityEvent,
          'coordination_item': RealtimeEntityKind.coordinationItem,
          'capability': RealtimeEntityKind.capability,
          'contact': RealtimeEntityKind.contact,
          'room_seen': RealtimeEntityKind.roomSeen,
          'relationship': RealtimeEntityKind.relationship,
          'profile': RealtimeEntityKind.profile,
          'notification': RealtimeEntityKind.notification,
        };

        for (final entry in wireKinds.entries) {
          wsMessages.add(
            _entityChange(
              entity: entry.key,
              id: '${entry.key}-id',
              event: 'insert',
              actorUserId: 'actor-1',
            ),
          );
        }
        async.elapse(const Duration(milliseconds: 500));

        expect(received.map((change) => change.kind).toSet(), wireKinds.values);
        expect(
          received,
          everyElement(
            isA<RealtimeEntityChange>()
                .having(
                  (change) => change.operation,
                  'operation',
                  RealtimeOperation.insert,
                )
                .having(
                  (change) => change.actorUserId,
                  'actorUserId',
                  'actor-1',
                )
                .having(
                  (change) => change.source,
                  'source',
                  RealtimeChangeSource.serverInvalidation,
                ),
          ),
        );

        unawaited(sub.cancel());
      });
    });

    test('ignores malformed and unknown entity-change payloads', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);
        wsMessages
          ..add(_entityChange(entity: 'unknown', id: 'b1'))
          ..add(_entityChange(entity: 'beacon', id: ''))
          ..add(_entityChange(entity: 'beacon', id: 'b1', event: 'upsert'))
          ..add({
            'type': 'subscription',
            'path': 'entity_changes',
            'payload': {
              'entity': 'beacon',
              'id': 'b1',
              'event': 'update',
              'actor_user_id': 42,
            },
          });
        async.elapse(const Duration(milliseconds: 500));

        expect(received, isEmpty);
        unawaited(sub.cancel());
      });
    });

    test('deduplicates by kind and aggregate id using the latest hint', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);
        wsMessages
          ..add(_entityChange(entity: 'beacon', id: 'b1', event: 'insert'))
          ..add(_entityChange(entity: 'beacon', id: 'b1'))
          ..add(_entityChange(entity: 'forward', id: 'b1', event: 'delete'));
        async.elapse(const Duration(milliseconds: 500));

        expect(received, hasLength(2));
        expect(
          received
              .singleWhere(
                (change) => change.kind == RealtimeEntityKind.beacon,
              )
              .operation,
          RealtimeOperation.update,
        );
        unawaited(sub.cancel());
      });
    });

    test('beacon room invalidations dedupe by beacon id and entity type', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <BeaconRoomInvalidation>[];
        final sub = service.beaconRoomInvalidations.listen(received.add);

        wsMessages.add(_entityChange(entity: 'room_message', id: 'room-1'));
        wsMessages.add(_entityChange(entity: 'room_message', id: 'room-1'));
        wsMessages.add(_entityChange(entity: 'participant', id: 'room-1'));
        async.elapse(const Duration(milliseconds: 500));

        expect(
          received.toSet(),
          {
            const BeaconRoomInvalidation(
              beaconId: 'room-1',
              entityType: BeaconRoomEntityType.roomMessage,
            ),
            const BeaconRoomInvalidation(
              beaconId: 'room-1',
              entityType: BeaconRoomEntityType.participant,
            ),
          },
        );

        unawaited(sub.cancel());
      });
    });

    test('separate debounce windows emit separate batches', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <String>[];
        final sub = service.beaconInvalidations.listen(received.add);

        wsMessages.add(_entityChange(entity: 'beacon', id: 'first'));
        async.elapse(const Duration(milliseconds: 500));
        expect(received, ['first']);

        wsMessages.add(_entityChange(entity: 'beacon', id: 'second'));
        async.elapse(const Duration(milliseconds: 500));
        expect(received, ['first', 'second']);

        unawaited(sub.cancel());
      });
    });
  });
}
