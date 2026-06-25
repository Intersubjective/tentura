import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';

Map<String, dynamic> _entityChange({
  required String entity,
  required String id,
}) =>
    {
      'type': 'subscription',
      'path': 'entity_changes',
      'payload': {'entity': entity, 'id': id},
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

        sub.cancel();
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

        sub.cancel();
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

        sub.cancel();
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

        forwardSub.cancel();
        helpSub.cancel();
        capSub.cancel();
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

        sub.cancel();
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

        sub.cancel();
      });
    });
  });
}
