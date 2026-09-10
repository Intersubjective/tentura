import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/data/gql/_g/beacon_threads_list.data.gql.dart';
import 'package:tentura/features/beacon_threads/data/model/request_thread_model.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

void main() {
  const seenAt = '2026-08-14T10:00:00.000Z';
  const messageAt = '2026-08-14T11:00:00.000Z';

  Map<String, Object?> threadRow({
    required String threadId,
    required String threadKind,
    String? lastSeenAt,
    Map<String, Object?>? preview,
  }) =>
      {
        '__typename': 'v2_BeaconThreadRow',
        'threadId': threadId,
        'threadKind': threadKind,
        'unreadCount': 2,
        'messageCount': 4,
        'lastSeenAt': lastSeenAt,
        'lastMessageAt': messageAt,
        'lastMessageAuthorId': 'Uauthor000001',
        'lastMessagePreview': preview,
      };

  RequestThread parseRow(Map<String, Object?> row) {
    final gql = GBeaconThreadsListData_beaconThreads.fromJson(row)!;
    return RequestThreadRowModel(gql).toEntity();
  }

  group('RequestThread general invariant', () {
    test('General row isGeneral by threadId', () {
      final thread = parseRow(
        threadRow(
          threadId: RequestThread.generalId,
          threadKind: 'general',
          lastSeenAt: seenAt,
        ),
      );

      expect(thread.threadId, RequestThread.generalId);
      expect(thread.kind, RequestThreadKind.general);
      expect(thread.item, isNull);
      expect(thread.isGeneral, isTrue);
      expect(thread.lastSeenAt, DateTime.parse(seenAt));
    });

    test('semantic row maps without embedded item', () {
      final thread = parseRow(
        threadRow(
          threadId: 'item-ask',
          threadKind: 'ask',
        ),
      );

      expect(thread.isGeneral, isFalse);
      expect(thread.item, isNull);
      expect(thread.kind, RequestThreadKind.ask);
    });
  });

  group('RequestThreadKind parsing', () {
    test('parses all four thread kinds', () {
      for (final entry in <String, RequestThreadKind>{
        'general': RequestThreadKind.general,
        'ask': RequestThreadKind.ask,
        'promise': RequestThreadKind.promise,
        'blocker': RequestThreadKind.blocker,
      }.entries) {
        final thread = parseRow(
          threadRow(
            threadId: entry.key == 'general' ? RequestThread.generalId : 'id',
            threadKind: entry.key,
          ),
        );
        expect(thread.kind, entry.value);
      }
    });

    test('rejects unknown threadKind', () {
      expect(
        () => parseRequestThreadKind('plan'),
        throwsArgumentError,
      );
    });
  });

  group('ThreadMessagePreview mapping', () {
    Map<String, Object?> preview({
      required int kind,
      String? excerpt,
      bool hasAttachment = false,
      String? joinedUserId,
      String? admissionReason,
      String? linkedItemId,
      int? linkedEventKind,
      int? itemKind,
      String? itemTitle,
      String? pollTitle,
      String? factTitle,
      int? factVisibility,
    }) =>
        {
          '__typename': 'v2_ThreadMessagePreview',
          'kind': kind,
          'excerpt': excerpt,
          'hasAttachment': hasAttachment,
          'joinedUserId': joinedUserId,
          'admissionReason': admissionReason,
          'linkedItemId': linkedItemId,
          'linkedEventKind': linkedEventKind,
          'itemKind': itemKind,
          'itemTitle': itemTitle,
          'pollTitle': pollTitle,
          'factTitle': factTitle,
          'factVisibility': factVisibility,
        };

    test('maps all preview kind codes 0-9', () {
      for (final code in ThreadMessagePreviewKind.values) {
        final thread = parseRow(
          threadRow(
            threadId: RequestThread.generalId,
            threadKind: 'general',
            preview: preview(kind: code, excerpt: 'excerpt-$code'),
          ),
        );
        expect(thread.lastMessagePreview?.kind, code);
      }
    });

    test('preserves nullable preview fields', () {
      final thread = parseRow(
        threadRow(
          threadId: RequestThread.generalId,
          threadKind: 'general',
          preview: preview(
            kind: ThreadMessagePreviewKind.coordination,
            hasAttachment: true,
            linkedItemId: 'item-1',
            linkedEventKind: 2,
            itemKind: 2,
            itemTitle: 'Ask title',
            pollTitle: 'Poll?',
            factTitle: 'Fact',
            factVisibility: 1,
            joinedUserId: 'Ujoin00000001',
            admissionReason: 'helpful',
          ),
        ),
      );

      final p = thread.lastMessagePreview!;
      expect(p.hasAttachment, isTrue);
      expect(p.linkedItemId, 'item-1');
      expect(p.linkedEventKind, 2);
      expect(p.itemKind, 2);
      expect(p.itemTitle, 'Ask title');
      expect(p.pollTitle, 'Poll?');
      expect(p.factTitle, 'Fact');
      expect(p.factVisibility, 1);
      expect(p.joinedUserId, 'Ujoin00000001');
      expect(p.admissionReason, 'helpful');
    });

    test('rejects out-of-range preview kind', () {
      expect(
        () => mapThreadMessagePreview(
          GBeaconThreadsListData_beaconThreads_lastMessagePreview.fromJson(
            preview(kind: 10),
          )!,
        ),
        throwsArgumentError,
      );
    });
  });

  group('semantic thread dates', () {
    test('maps semantic lastSeenAt and lastMessageAt', () {
      final thread = parseRow(
        threadRow(
          threadId: 'item-ask',
          threadKind: 'ask',
          lastSeenAt: seenAt,
        ),
      );

      expect(thread.isGeneral, isFalse);
      expect(thread.lastSeenAt, DateTime.parse(seenAt));
      expect(thread.lastMessageAt, DateTime.parse(messageAt));
      expect(thread.isActive, isTrue);
    });
  });
}
