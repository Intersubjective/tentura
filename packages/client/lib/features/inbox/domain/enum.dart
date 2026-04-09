/// Inbox row state (maps to DB `inbox_item.status` smallint).
enum InboxItemStatus {
  /// 0
  needsMe,

  /// 1
  watching,

  /// 2
  rejected,

  /// 3 — beacon closed before recipient triaged (passive tombstone)
  closedBeforeResponse,

  /// 4 — beacon deleted (lifecycle) before recipient triaged
  deletedBeforeResponse,
}

extension InboxItemStatusSmallint on InboxItemStatus {
  int get toSmallint => switch (this) {
    InboxItemStatus.needsMe => 0,
    InboxItemStatus.watching => 1,
    InboxItemStatus.rejected => 2,
    InboxItemStatus.closedBeforeResponse => 3,
    InboxItemStatus.deletedBeforeResponse => 4,
  };
}

InboxItemStatus inboxItemStatusFromSmallint(int value) => switch (value) {
  1 => InboxItemStatus.watching,
  2 => InboxItemStatus.rejected,
  3 => InboxItemStatus.closedBeforeResponse,
  4 => InboxItemStatus.deletedBeforeResponse,
  _ => InboxItemStatus.needsMe,
};

enum InboxSort {
  recent,
  meritRank,
  deadline,
}
