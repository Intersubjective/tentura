import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/beacon_threads_list.data.gql.dart';
import 'package:tentura/features/beacon_threads/data/model/request_thread_model.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/coordination_item/data/gql/_g/coordination_item_list.data.gql.dart';
import 'package:tentura/features/coordination_item/data/model/coordination_item_model.dart';

void main() {
  const beaconId = 'Bbeacon0000001';
  const seenAt = '2026-08-14T10:00:00.000Z';
  const messageAt = '2026-08-14T11:00:00.000Z';

  Map<String, Object?> itemFields({
    required String id,
    int kind = 2,
    String? lastSeenAt,
  }) =>
      {
        '__typename': 'v2_CoordinationItemRow',
        'id': id,
        'beaconId': beaconId,
        'kind': kind,
        'status': 0,
        'source': 1,
        'published': true,
        'title': 'Title $id',
        'body': 'Body $id',
        'creatorId': 'Ucreator00001',
        'targetPersonId': 'Utarget000001',
        'acceptedById': null,
        'targetItemId': null,
        'targetMessageId': null,
        'linkedMessageId': null,
        'linkedParentItemId': null,
        'ordering': 0,
        'createdAt': '2026-08-01T00:00:00.000Z',
        'updatedAt': '2026-08-02T00:00:00.000Z',
        'resolvedAt': null,
        'cancelledAt': null,
        'staleAt': null,
        'lastRemindedAt': null,
        'staleAfterDays': 3,
        'messageCount': 4,
        'unreadCount': 2,
        'lastSeenAt': lastSeenAt,
      };

  Map<String, Object?> threadRow({
    required String threadId,
    required String threadKind,
    Map<String, Object?>? item,
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
        'item': item,
      };

  RequestThread parseRow(Map<String, Object?> row) {
    final gql = GBeaconThreadsListData_beaconThreads.fromJson(row)!;
    return RequestThreadRowModel(gql).toEntity();
  }

  group('RequestThread general invariant', () {
    test('General row has null item and isGeneral', () {
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

    test('semantic row requires embedded item', () {
      expect(
        () => parseRow(
          threadRow(
            threadId: 'item-ask',
            threadKind: 'ask',
          ),
        ),
        throwsStateError,
      );
    });

    test('General row rejects embedded item', () {
      expect(
        () => parseRow(
          threadRow(
            threadId: RequestThread.generalId,
            threadKind: 'general',
            item: itemFields(id: 'item-ask'),
          ),
        ),
        throwsStateError,
      );
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
            item: entry.key == 'general'
                ? null
                : itemFields(
                    id: 'id',
                    kind: switch (entry.value) {
                      RequestThreadKind.ask => 2,
                      RequestThreadKind.blocker => 3,
                      RequestThreadKind.promise => 5,
                      RequestThreadKind.general => 2,
                    },
                  ),
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

  group('semantic thread dates and item', () {
    test('maps semantic lastSeenAt and lastMessageAt', () {
      final thread = parseRow(
        threadRow(
          threadId: 'item-ask',
          threadKind: 'ask',
          lastSeenAt: seenAt,
          item: itemFields(id: 'item-ask', lastSeenAt: seenAt),
        ),
      );

      expect(thread.isGeneral, isFalse);
      expect(thread.lastSeenAt, DateTime.parse(seenAt));
      expect(thread.lastMessageAt, DateTime.parse(messageAt));
      expect(thread.item?.lastSeenAt, DateTime.parse(seenAt));
      expect(thread.isActive, isTrue);
    });
  });

  test('embedded item matches CoordinationItemListModel mapping', () {
    final fields = itemFields(id: 'item-parity', kind: 5, lastSeenAt: seenAt);
    final fromList = CoordinationItemListModel(
      GCoordinationItemListData_coordinationItemsByBeacon.fromJson(fields)!,
    ).toEntity();
    final fromThread = mapEmbeddedThreadItem(
      GBeaconThreadsListData_beaconThreads_item.fromJson(fields)!,
    );

    expect(fromThread, fromList);
    expect(fromThread.kind, CoordinationItemKind.promise);
    expect(fromThread.messageCount, 4);
    expect(fromThread.unreadCount, 2);
  });
}
