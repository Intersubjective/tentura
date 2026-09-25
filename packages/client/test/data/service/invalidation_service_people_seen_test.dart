// Issue #178 part 2: `people_seen` frames (author/steward opened the People
// surface) must reach subscribers so the offerer's pending-offer label can
// flip in place. Today `RealtimeEntityKind.fromWire('people_seen')` is null
// and the frame is dropped.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

Map<String, dynamic> _peopleSeenFrame({
  required String beaconId,
  String lastSeenAt = '2026-06-15T12:05:00.000Z',
}) => {
  'type': 'subscription',
  'path': 'entity_changes',
  'payload': {
    'entity': 'people_seen',
    'id': beaconId,
    'event': 'update',
    'actor_user_id': 'Uauthor000001',
    'last_seen_at': lastSeenAt,
  },
};

void main() {
  group('InvalidationService people_seen', () {
    test('people_seen is a known wire kind', () {
      expect(RealtimeEntityKind.fromWire('people_seen'), isNotNull);
    });

    test('valid frame yields one change for the request', () {
      fakeAsync((async) {
        final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
        final service = InvalidationService.forTesting(wsMessages.stream);
        addTearDown(() async {
          await service.dispose();
          await wsMessages.close();
        });

        final received = <RealtimeEntityChange>[];
        final sub = service.entityChanges.listen(received.add);

        wsMessages.add(_peopleSeenFrame(beaconId: 'Bpeopleseen01'));
        async.elapse(const Duration(milliseconds: 100));

        expect(received, hasLength(1));
        expect(received.single.aggregateId, 'Bpeopleseen01');
        expect(
          received.single.peopleSeenAt,
          DateTime.utc(2026, 6, 15, 12, 5),
        );
        expect(
          received.single.kind,
          RealtimeEntityKind.fromWire('people_seen'),
        );
        expect(received.single.kind, isNotNull);

        unawaited(sub.cancel());
      });
    });

    test('frames for different requests both emit in one batch', () {
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
          ..add(_peopleSeenFrame(beaconId: 'Bpeopleseen01'))
          ..add(_peopleSeenFrame(beaconId: 'Bpeopleseen02'));
        async.elapse(const Duration(milliseconds: 100));

        expect(received.map((c) => c.aggregateId).toSet(), {
          'Bpeopleseen01',
          'Bpeopleseen02',
        });

        unawaited(sub.cancel());
      });
    });
  });
}
