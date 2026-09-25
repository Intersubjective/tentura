// tentura-fpi landing gate acceptance (chat read receipts / room_seen_peer)

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_seen_peer.dart';

Map<String, dynamic> _roomSeenPeerFrame({
  required String beaconId,
  String? seenUserId,
  String? lastSeenAt,
  String event = 'update',
  String? actorUserId,
}) {
  return {
    'type': 'subscription',
    'path': 'entity_changes',
    'payload': {
      'entity': 'room_seen_peer',
      'id': beaconId,
      'event': event,
      if (actorUserId != null) 'actor_user_id': actorUserId,
      if (seenUserId != null) 'seen_user_id': seenUserId,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
    },
  };
}

void main() {
  group('InvalidationService room_seen_peer', () {
    const beaconId = 'Bseenpeer0001';
    const seenUserId = 'Ugggggggggggg';
    const lastSeenAtWire = '2026-06-15T12:00:00.000Z';

    test('valid frame yields roomSeenPeer change with parsed seenPeer', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);

        wsMessages.add(
          _roomSeenPeerFrame(
            beaconId: beaconId,
            seenUserId: seenUserId,
            lastSeenAt: lastSeenAtWire,
          ),
        );
        async.elapse(const Duration(milliseconds: 100));

        expect(received, hasLength(1));
        final change = received.single;
        expect(change.kind, RealtimeEntityKind.roomSeenPeer);
        expect(change.aggregateId, beaconId);
        expect(
          change.seenPeer,
          RealtimeSeenPeer(
            userId: seenUserId,
            lastSeenAt: DateTime.utc(2026, 6, 15, 12),
          ),
        );
        expect(change.seenPeer?.lastSeenAt.isUtc, isTrue);

        unawaited(sub.cancel());
      });
    });

    test('drops frame when last_seen_at is missing', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);

        wsMessages.add(
          _roomSeenPeerFrame(
            beaconId: beaconId,
            seenUserId: seenUserId,
          ),
        );
        async.elapse(const Duration(milliseconds: 100));

        expect(received, isEmpty);

        unawaited(sub.cancel());
      });
    });

    test('drops frame when seen_user_id is missing', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);

        wsMessages.add(
          _roomSeenPeerFrame(
            beaconId: beaconId,
            lastSeenAt: lastSeenAtWire,
          ),
        );
        async.elapse(const Duration(milliseconds: 100));

        expect(received, isEmpty);

        unawaited(sub.cancel());
      });
    });

    test('different seen_user_id for same beacon both emit in one batch', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);

        wsMessages.add(
          _roomSeenPeerFrame(
            beaconId: beaconId,
            seenUserId: 'Upeer00000001',
            lastSeenAt: lastSeenAtWire,
          ),
        );
        wsMessages.add(
          _roomSeenPeerFrame(
            beaconId: beaconId,
            seenUserId: 'Upeer00000002',
            lastSeenAt: lastSeenAtWire,
          ),
        );
        async.elapse(const Duration(milliseconds: 100));

        expect(received, hasLength(2));
        expect(
          received.map((change) => change.seenPeer?.userId).toSet(),
          {'Upeer00000001', 'Upeer00000002'},
        );

        unawaited(sub.cancel());
      });
    });

    test('same seen_user_id for same beacon collapses to one', () {
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
          wsMessages.add(
            _roomSeenPeerFrame(
              beaconId: beaconId,
              seenUserId: seenUserId,
              lastSeenAt: lastSeenAtWire,
            ),
          );
        }
        async.elapse(const Duration(milliseconds: 100));

        expect(received, hasLength(1));
        expect(received.single.seenPeer?.userId, seenUserId);

        unawaited(sub.cancel());
      });
    });
  });
}
