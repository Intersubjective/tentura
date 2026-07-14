import 'dart:convert';
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/realtime_transport_status.dart';
import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_watch.dart';
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

RealtimeTransportStatus _transport({
  required String? accountId,
  required int epoch,
  required RealtimeTransportPhase phase,
  RealtimeReconnectCause cause = RealtimeReconnectCause.network,
}) => RealtimeTransportStatus(
  accountId: accountId,
  connectionEpoch: epoch,
  phase: phase,
  cause: cause,
);

void main() {
  group('InvalidationService', () {
    test('registers and removes watches using opaque subscription frames', () {
      final sent = <Object>[];
      final service = InvalidationService.forTesting(
        const Stream.empty(),
        send: sent.add,
      );
      addTearDown(service.dispose);

      service
        ..replaceWatch(
          RealtimeWatchGrant(
            token: 'signed-value',
            scope: RealtimeWatchScope.profile,
            authorizedSubjectIds: const {'user-a'},
            expiresAt: DateTime.utc(2026, 7, 14, 12, 2),
          ),
        )
        ..removeWatch(RealtimeWatchScope.profile);

      expect(jsonDecode(sent.first as String), {
        'type': 'subscription',
        'path': 'entity_changes',
        'payload': {
          'intent': 'replace_watch',
          'scope': 'profile',
          'grant': 'signed-value',
        },
      });
      expect(jsonDecode(sent.last as String), {
        'type': 'subscription',
        'path': 'entity_changes',
        'payload': {'intent': 'remove_watch', 'scope': 'profile'},
      });
    });

    test('ignores non-entity_changes websocket frames', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);

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

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);

        for (var i = 0; i < 5; i++) {
          wsMessages.add(_entityChange(entity: 'beacon', id: 'beacon-1'));
        }
        async.elapse(const Duration(milliseconds: 100));
        expect(received, isEmpty);

        async.elapse(const Duration(milliseconds: 500));
        expect(received.map((change) => change.aggregateId), ['beacon-1']);

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

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);

        wsMessages.add(_entityChange(entity: 'beacon', id: 'beacon-a'));
        wsMessages.add(_entityChange(entity: 'beacon', id: 'beacon-b'));
        wsMessages.add(_entityChange(entity: 'beacon', id: 'beacon-a'));
        async.elapse(const Duration(milliseconds: 500));

        expect(
          received.map((change) => change.aggregateId).toSet(),
          {'beacon-a', 'beacon-b'},
        );

        unawaited(sub.cancel());
      });
    });

    test('routes entity types through the shared typed stream', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);

        wsMessages.add(_entityChange(entity: 'forward', id: 'f1'));
        wsMessages.add(_entityChange(entity: 'help_offer', id: 'h1'));
        wsMessages.add(
          _entityChange(entity: 'person_capability_event', id: 'u1'),
        );
        async.elapse(const Duration(milliseconds: 500));

        expect(
          received.map((change) => (change.kind, change.aggregateId)).toSet(),
          {
            (RealtimeEntityKind.forward, 'f1'),
            (RealtimeEntityKind.helpOffer, 'h1'),
            (RealtimeEntityKind.capability, 'u1'),
          },
        );

        unawaited(sub.cancel());
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

    test('first authentication is quiet and reconnect emits one catch-up', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final transport = StreamController<RealtimeTransportStatus>.broadcast();
        final service = InvalidationService.forTesting(
          wsMessages.stream,
          transportStatuses: transport.stream,
        );
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
          await transport.close();
        });

        final received = <RealtimeCatchUp>[];
        final sub = service.catchUps.listen(received.add);
        transport
          ..add(
            _transport(
              accountId: 'account-a',
              epoch: 1,
              phase: RealtimeTransportPhase.authenticating,
              cause: RealtimeReconnectCause.initial,
            ),
          )
          ..add(
            _transport(
              accountId: 'account-a',
              epoch: 1,
              phase: RealtimeTransportPhase.authenticated,
              cause: RealtimeReconnectCause.initial,
            ),
          );
        async.elapse(const Duration(milliseconds: 500));
        expect(received, isEmpty);

        transport
          ..add(
            _transport(
              accountId: 'account-a',
              epoch: 2,
              phase: RealtimeTransportPhase.authenticating,
            ),
          )
          ..add(
            _transport(
              accountId: 'account-a',
              epoch: 2,
              phase: RealtimeTransportPhase.authenticated,
            ),
          );
        async.elapse(const Duration(milliseconds: 500));

        expect(
          received,
          [
            const RealtimeCatchUp(
              accountId: 'account-a',
              connectionEpoch: 2,
              reason: RealtimeCatchUpReason.webSocketReconnected,
            ),
          ],
        );
        unawaited(sub.cancel());
      });
    });

    test('pong reconstruction preserves its typed catch-up reason', () {
      fakeAsync((async) {
        final transport = StreamController<RealtimeTransportStatus>.broadcast();
        final service = InvalidationService.forTesting(
          const Stream.empty(),
          transportStatuses: transport.stream,
        );
        addTearDown(() async {
          await service.dispose();
          await transport.close();
        });

        final received = <RealtimeCatchUp>[];
        final sub = service.catchUps.listen(received.add);
        transport
          ..add(
            _transport(
              accountId: 'account-a',
              epoch: 1,
              phase: RealtimeTransportPhase.authenticated,
              cause: RealtimeReconnectCause.initial,
            ),
          )
          ..add(
            _transport(
              accountId: 'account-a',
              epoch: 2,
              phase: RealtimeTransportPhase.authenticated,
              cause: RealtimeReconnectCause.pongTimeout,
            ),
          );
        async.elapse(const Duration(milliseconds: 500));

        expect(received.single.reason, RealtimeCatchUpReason.pongTimeout);
        unawaited(sub.cancel());
      });
    });

    test('account switch rejects late old-account connection transitions', () {
      fakeAsync((async) {
        final transport = StreamController<RealtimeTransportStatus>.broadcast();
        final service = InvalidationService.forTesting(
          const Stream.empty(),
          transportStatuses: transport.stream,
        );
        addTearDown(() async {
          await service.dispose();
          await transport.close();
        });

        final catchUps = <RealtimeCatchUp>[];
        final statuses = <RealtimeConnectionStatus>[];
        final catchUpSub = service.catchUps.listen(catchUps.add);
        final statusSub = service.connectionStatuses.listen(statuses.add);
        transport
          ..add(
            _transport(
              accountId: 'account-a',
              epoch: 1,
              phase: RealtimeTransportPhase.authenticated,
              cause: RealtimeReconnectCause.initial,
            ),
          )
          ..add(
            _transport(
              accountId: 'account-b',
              epoch: 2,
              phase: RealtimeTransportPhase.connecting,
              cause: RealtimeReconnectCause.initial,
            ),
          )
          ..add(
            _transport(
              accountId: 'account-a',
              epoch: 1,
              phase: RealtimeTransportPhase.authenticated,
            ),
          )
          ..add(
            _transport(
              accountId: 'account-b',
              epoch: 2,
              phase: RealtimeTransportPhase.authenticated,
              cause: RealtimeReconnectCause.initial,
            ),
          );
        async.elapse(const Duration(milliseconds: 500));

        expect(catchUps, isEmpty);
        expect(statuses.last.accountId, 'account-b');
        unawaited(catchUpSub.cancel());
        unawaited(statusSub.cancel());
      });
    });

    test('server listener recovery emits a jittered typed catch-up', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final transport = StreamController<RealtimeTransportStatus>.broadcast();
        final service = InvalidationService.forTesting(
          wsMessages.stream,
          transportStatuses: transport.stream,
        );
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
          await transport.close();
        });

        final received = <RealtimeCatchUp>[];
        final sub = service.catchUps.listen(received.add);
        transport.add(
          _transport(
            accountId: 'account-a',
            epoch: 7,
            phase: RealtimeTransportPhase.authenticated,
            cause: RealtimeReconnectCause.initial,
          ),
        );
        async.flushMicrotasks();
        wsMessages.add({
          'type': 'control',
          'path': 'entity_changes',
          'payload': {
            'intent': 'catch_up',
            'reason': 'pg_listener_recovered',
          },
        });
        async.elapse(const Duration(milliseconds: 500));

        expect(
          received.single.reason,
          RealtimeCatchUpReason.pgListenerRecovered,
        );
        expect(received.single.shouldJitter, isTrue);
        expect(received.single.connectionEpoch, 7);
        unawaited(sub.cancel());
      });
    });

    test('explicit resume catch-up is account and epoch scoped', () {
      fakeAsync((async) {
        final transport = StreamController<RealtimeTransportStatus>.broadcast();
        final service = InvalidationService.forTesting(
          const Stream.empty(),
          transportStatuses: transport.stream,
        );
        addTearDown(() async {
          await service.dispose();
          await transport.close();
        });

        final received = <RealtimeCatchUp>[];
        final sub = service.catchUps.listen(received.add);
        service.requestCatchUp(RealtimeCatchUpReason.appResumed);
        transport.add(
          _transport(
            accountId: 'account-a',
            epoch: 4,
            phase: RealtimeTransportPhase.connecting,
          ),
        );
        async.flushMicrotasks();
        service.requestCatchUp(RealtimeCatchUpReason.appResumed);
        async.elapse(const Duration(milliseconds: 500));

        expect(
          received,
          [
            const RealtimeCatchUp(
              accountId: 'account-a',
              connectionEpoch: 4,
              reason: RealtimeCatchUpReason.appResumed,
            ),
          ],
        );
        unawaited(sub.cancel());
      });
    });

    test('room projection adapter consumes the shared typed stream', () {
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

        wsMessages.add(_entityChange(entity: 'room_message', id: 'room-1'));
        wsMessages.add(_entityChange(entity: 'room_message', id: 'room-1'));
        wsMessages.add(_entityChange(entity: 'participant', id: 'room-1'));
        wsMessages.add(_entityChange(entity: 'room_reaction', id: 'room-1'));
        wsMessages.add(_entityChange(entity: 'room_poll', id: 'room-1'));
        wsMessages.add(_entityChange(entity: 'room_seen', id: 'room-1'));
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
            const BeaconRoomInvalidation(
              beaconId: 'room-1',
              entityType: BeaconRoomEntityType.roomReaction,
            ),
            const BeaconRoomInvalidation(
              beaconId: 'room-1',
              entityType: BeaconRoomEntityType.roomPoll,
            ),
            const BeaconRoomInvalidation(
              beaconId: 'room-1',
              entityType: BeaconRoomEntityType.roomSeen,
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

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);

        wsMessages.add(_entityChange(entity: 'beacon', id: 'first'));
        async.elapse(const Duration(milliseconds: 500));
        expect(received.map((change) => change.aggregateId), ['first']);

        wsMessages.add(_entityChange(entity: 'beacon', id: 'second'));
        async.elapse(const Duration(milliseconds: 500));
        expect(
          received.map((change) => change.aggregateId),
          ['first', 'second'],
        );

        unawaited(sub.cancel());
      });
    });
  });
}
