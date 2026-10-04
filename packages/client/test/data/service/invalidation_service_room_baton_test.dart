import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';

Map<String, dynamic> _roomBatonFrame({
  required String beaconId,
  String event = 'update',
  String? actorUserId,
}) {
  return {
    'type': 'subscription',
    'path': 'entity_changes',
    'payload': {
      'entity': 'room_baton',
      'id': beaconId,
      'event': event,
      if (actorUserId != null) 'actor_user_id': actorUserId,
    },
  };
}

void main() {
  group('RealtimeEntityKind room_baton wire mapping', () {
    test('room_baton maps to RealtimeEntityKind.roomBaton', () {
      expect(
        RealtimeEntityKind.fromWire('room_baton'),
        RealtimeEntityKind.roomBaton,
      );
    });
  });

  group('InvalidationService room_baton', () {
    const beaconId = 'Bbaton0000001';

    test('frame yields a roomBaton change keyed by the room id', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);

        wsMessages.add(_roomBatonFrame(beaconId: beaconId));
        async.elapse(const Duration(milliseconds: 100));

        expect(received, hasLength(1));
        expect(received.single.kind, RealtimeEntityKind.roomBaton);
        expect(received.single.aggregateId, beaconId);
        expect(received.single.operation, RealtimeOperation.update);

        unawaited(sub.cancel());
      });
    });

    test('frame reaches the room invalidation stream as roomBaton', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <BeaconRoomInvalidation>[];
        final sub = service.entityChanges
            .map(BeaconRoomInvalidation.fromRealtimeChange)
            .where((invalidation) => invalidation != null)
            .cast<BeaconRoomInvalidation>()
            .listen(received.add);

        wsMessages.add(_roomBatonFrame(beaconId: beaconId));
        async.elapse(const Duration(milliseconds: 100));

        expect(received, [
          BeaconRoomInvalidation(
            beaconId: beaconId,
            entityType: BeaconRoomEntityType.roomBaton,
            operation: RealtimeOperation.update,
          ),
        ]);

        unawaited(sub.cancel());
      });
    });

    test('repeated frames for one room collapse to a single change', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);

        for (var i = 0; i < 3; i++) {
          wsMessages.add(_roomBatonFrame(beaconId: beaconId));
        }
        async.elapse(const Duration(milliseconds: 100));

        expect(received, hasLength(1));

        unawaited(sub.cancel());
      });
    });
  });

  group('BeaconRoomInvalidation.fromRealtimeChange room_baton', () {
    test('maps roomBaton change to the roomBaton room entity type', () {
      const change = RealtimeEntityChange(
        kind: RealtimeEntityKind.roomBaton,
        aggregateId: 'Bbaton0000001',
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
      );

      final invalidation = BeaconRoomInvalidation.fromRealtimeChange(change);

      expect(invalidation, isNotNull);
      expect(invalidation!.beaconId, 'Bbaton0000001');
      expect(invalidation.entityType, BeaconRoomEntityType.roomBaton);
    });
  });
}
