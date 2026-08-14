import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/coordination_item/data/model/coordination_item_model.dart';

import '../../domain/entity/request_thread.dart';
import '../gql/_g/beacon_threads_list.data.gql.dart';

RequestThreadKind parseRequestThreadKind(String raw) => switch (raw) {
      'general' => RequestThreadKind.general,
      'ask' => RequestThreadKind.ask,
      'promise' => RequestThreadKind.promise,
      'blocker' => RequestThreadKind.blocker,
      _ => throw ArgumentError.value(raw, 'threadKind'),
    };

ThreadMessagePreview mapThreadMessagePreview(
  GBeaconThreadsListData_beaconThreads_lastMessagePreview preview,
) {
  final kind = preview.kind;
  if (!ThreadMessagePreviewKind.values.contains(kind)) {
    throw ArgumentError.value(kind, 'preview.kind');
  }
  return ThreadMessagePreview(
    kind: kind,
    excerpt: preview.excerpt,
    hasAttachment: preview.hasAttachment,
    joinedUserId: preview.joinedUserId,
    admissionReason: preview.admissionReason,
    linkedItemId: preview.linkedItemId,
    linkedEventKind: preview.linkedEventKind,
    itemKind: preview.itemKind,
    itemTitle: preview.itemTitle,
    pollTitle: preview.pollTitle,
    factTitle: preview.factTitle,
    factVisibility: preview.factVisibility,
  );
}

CoordinationItem mapEmbeddedThreadItem(
  GBeaconThreadsListData_beaconThreads_item item,
) =>
    coordinationItemFromFields(
      id: item.id,
      beaconId: item.beaconId,
      kind: item.kind,
      status: item.status,
      source: item.source,
      published: item.published,
      title: item.title,
      body: item.body,
      creatorId: item.creatorId,
      targetPersonId: item.targetPersonId,
      acceptedById: item.acceptedById,
      targetItemId: item.targetItemId,
      targetMessageId: item.targetMessageId,
      linkedMessageId: item.linkedMessageId,
      linkedParentItemId: item.linkedParentItemId,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      resolvedAt: item.resolvedAt,
      cancelledAt: item.cancelledAt,
      staleAt: item.staleAt,
      lastRemindedAt: item.lastRemindedAt,
      staleAfterDays: item.staleAfterDays,
      messageCount: item.messageCount,
      unreadCount: item.unreadCount,
      lastSeenAt: item.lastSeenAt,
    );

DateTime? _parseOptionalDate(String? raw) =>
    raw == null || raw.isEmpty ? null : DateTime.parse(raw);

void _assertGeneralItemInvariant({
  required String threadId,
  required CoordinationItem? item,
}) {
  final isGeneral = threadId == RequestThread.generalId;
  if (isGeneral && item != null) {
    throw StateError('General thread must not carry an embedded item');
  }
  if (!isGeneral && item == null) {
    throw StateError('Semantic thread must carry an embedded item');
  }
}

extension type const RequestThreadRowModel(GBeaconThreadsListData_beaconThreads i)
    implements GBeaconThreadsListData_beaconThreads {
  RequestThread toEntity() {
    final item = i.item == null ? null : mapEmbeddedThreadItem(i.item!);
    _assertGeneralItemInvariant(threadId: i.threadId, item: item);
    final preview = i.lastMessagePreview;
    return RequestThread(
      threadId: i.threadId,
      kind: parseRequestThreadKind(i.threadKind),
      unreadCount: i.unreadCount,
      messageCount: i.messageCount,
      lastSeenAt: _parseOptionalDate(i.lastSeenAt),
      lastMessageAt: _parseOptionalDate(i.lastMessageAt),
      lastMessageAuthorId: i.lastMessageAuthorId,
      lastMessagePreview:
          preview == null ? null : mapThreadMessagePreview(preview),
      item: item,
    );
  }
}
