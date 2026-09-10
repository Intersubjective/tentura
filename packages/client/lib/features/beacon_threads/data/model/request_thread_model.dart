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

DateTime? _parseOptionalDate(String? raw) =>
    raw == null || raw.isEmpty ? null : DateTime.parse(raw);

extension type const RequestThreadRowModel(GBeaconThreadsListData_beaconThreads i)
    implements GBeaconThreadsListData_beaconThreads {
  RequestThread toEntity() {
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
      item: null,
    );
  }
}
