// Issue #178 part 2: `people_seen` frames (author/steward opened the People
// surface) must reach subscribers so the offerer's pending-offer label can
// flip in place. The batch dedup key must include the watermark so distinct
// `last_seen_at` values for one request are both delivered.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

Map<String, dynamic> _peopleSeenFrame({
  required String beaconId,
  Object? lastSeenAt = '2026-06-15T12:05:00.000Z',
  bool omitLastSeenAt = false,
}) => {
  'type': 'subscription',
  'path': 'entity_changes',
  'payload': {
    'entity': 'people_seen',
    'id': beaconId,
    'event': 'update',
    'actor_user_id': 'Uauthor000001',
    if (!omitLastSeenAt) 'last_seen_at': lastSeenAt,
  },
};

void main() {
  group('InvalidationService people_seen', () {
    test('people_seen is a known wire kind', () {
      expect(
        RealtimeEntityKind.fromWire('people_seen'),
        RealtimeEntityKind.peopleSeen,
      );
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
        expect(received.single.kind, RealtimeEntityKind.peopleSeen);

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

    for (final entry in <String, Map<String, dynamic>>{
      'missing': _peopleSeenFrame(beaconId: 'Bpeopleseen03', omitLastSeenAt: true),
      'unparsable': _peopleSeenFrame(
        beaconId: 'Bpeopleseen03',
        lastSeenAt: 'not-a-date',
      ),
      'non-string': _peopleSeenFrame(beaconId: 'Bpeopleseen03', lastSeenAt: 42),
    }.entries) {
      test('frame with ${entry.key} last_seen_at is dropped', () {
        fakeAsync((async) {
          final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
          final service = InvalidationService.forTesting(wsMessages.stream);
          addTearDown(() async {
            await service.dispose();
            await wsMessages.close();
          });

          final received = <RealtimeEntityChange>[];
          final sub = service.entityChanges.listen(received.add);

          wsMessages.add(entry.value);
          async.elapse(const Duration(milliseconds: 100));

          expect(received, isEmpty);
          unawaited(sub.cancel());
        });
      });
    }

    test('peopleSeenAt is UTC even for an offset timestamp', () {
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
          _peopleSeenFrame(
            beaconId: 'Bpeopleseen01',
            lastSeenAt: '2026-06-15T14:05:00+02:00',
          ),
        );
        async.elapse(const Duration(milliseconds: 100));

        expect(received.single.peopleSeenAt!.isUtc, isTrue);
        expect(received.single.peopleSeenAt, DateTime.utc(2026, 6, 15, 12, 5));
        unawaited(sub.cancel());
      });
    });

    test('peopleSeenAt is UTC for a timestamp without an offset', () {
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
          _peopleSeenFrame(
            beaconId: 'Bpeopleseen01',
            lastSeenAt: '2026-06-15T12:05:00',
          ),
        );
        async.elapse(const Duration(milliseconds: 100));

        expect(received, hasLength(1));
        expect(received.single.peopleSeenAt!.isUtc, isTrue);
        expect(
          received.single.peopleSeenAt,
          DateTime.parse('2026-06-15T12:05:00').toUtc(),
        );
        unawaited(sub.cancel());
      });
    });

    test('same request, different last_seen_at in one batch: both emit', () {
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
          ..add(
            _peopleSeenFrame(
              beaconId: 'Bpeopleseen01',
              lastSeenAt: '2026-06-15T12:10:00.000Z',
            ),
          );
        async.elapse(const Duration(milliseconds: 100));

        expect(received.map((c) => c.peopleSeenAt), [
          DateTime.utc(2026, 6, 15, 12, 5),
          DateTime.utc(2026, 6, 15, 12, 10),
        ]);
        unawaited(sub.cancel());
      });
    });

    test('same request, identical last_seen_at in one batch: collapse', () {
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
          ..add(_peopleSeenFrame(beaconId: 'Bpeopleseen01'));
        async.elapse(const Duration(milliseconds: 100));

        expect(received, hasLength(1));
        unawaited(sub.cancel());
      });
    });
  });
}
