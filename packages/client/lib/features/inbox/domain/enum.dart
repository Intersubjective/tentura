/// Inbox row state (maps to DB `inbox_item.status` smallint).
enum InboxItemStatus {
  /// 0
  needsMe,

  /// 1
  watching,

  /// 2
  rejected,
}

extension InboxItemStatusSmallint on InboxItemStatus {
  int get toSmallint => switch (this) {
    InboxItemStatus.needsMe => 0,
    InboxItemStatus.watching => 1,
    InboxItemStatus.rejected => 2,
  };
}

InboxItemStatus inboxItemStatusFromSmallint(int value) => switch (value) {
  1 => InboxItemStatus.watching,
  2 => InboxItemStatus.rejected,
  _ => InboxItemStatus.needsMe,
};

enum InboxSort {
  recent,
  meritRank,
  deadline,
}
