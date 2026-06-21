import 'package:test/test.dart';

import 'package:tentura_server/data/repository/coordination_item_repository.dart';

void main() {
  group('CoordinationItemRepository.roomBodyForCreatedItem', () {
    test('uses title only when body empty', () {
      expect(
        CoordinationItemRepository.roomBodyForCreatedItem(
          title: 'Blocked on API',
        ),
        'Blocked on API',
      );
    });

    test('joins title and body when both present', () {
      expect(
        CoordinationItemRepository.roomBodyForCreatedItem(
          title: 'Ask',
          body: 'Need the file by Friday',
        ),
        'Ask\nNeed the file by Friday',
      );
    });

    test('uses body only when title empty', () {
      expect(
        CoordinationItemRepository.roomBodyForCreatedItem(
          title: '  ',
          body: 'Details only',
        ),
        'Details only',
      );
    });
  });

  group('CoordinationItemRepository.mergeSystemPayload', () {
    test('preserves existing keys when patching lastStatusEvent', () {
      final merged = CoordinationItemRepository.mergeSystemPayload(
        <String, Object?>{'semanticActorId': 'u-done'},
        <String, Object?>{
          'lastStatusEvent': <String, Object?>{
            'eventKind': 3,
            'actorId': 'u-resolve',
            'at': '2026-05-21T12:00:00.000Z',
          },
        },
      );

      expect(merged['semanticActorId'], 'u-done');
      expect(merged['lastStatusEvent'], isA<Map>());
      final ev = merged['lastStatusEvent']! as Map;
      expect(ev['eventKind'], 3);
      expect(ev['actorId'], 'u-resolve');
    });

    test('deep-merges nested lastStatusEvent without dropping sibling maps', () {
      final merged = CoordinationItemRepository.mergeSystemPayload(
        <String, Object?>{
          'lastStatusEvent': <String, Object?>{'eventKind': 1},
          'other': <String, Object?>{'a': 1},
        },
        <String, Object?>{
          'lastStatusEvent': <String, Object?>{
            'actorId': 'u2',
            'at': '2026-05-21T13:00:00.000Z',
          },
        },
      );

      final ev = merged['lastStatusEvent']! as Map;
      expect(ev['eventKind'], 1);
      expect(ev['actorId'], 'u2');
      expect((merged['other']! as Map)['a'], 1);
    });

    test('notify row payload shape for anchored status event', () {
      const anchorId = 'Rsourceaaaaaa';
      final notifyPayload = <String, Object?>{'sourceMessageId': anchorId};
      expect(notifyPayload['sourceMessageId'], anchorId);

      final sourcePatch = CoordinationItemRepository.mergeSystemPayload(
        null,
        <String, Object?>{
          'lastStatusEvent': <String, Object?>{
            'eventKind': 3,
            'actorId': 'u1',
            'at': '2026-05-21T12:00:00.000Z',
          },
        },
      );
      expect(sourcePatch.containsKey('lastStatusEvent'), isTrue);
    });
  });
}
