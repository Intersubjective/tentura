// Coordination item source (origin); persisted on `coordination_item.source`.
const int coordinationItemSourceDefault = 0;

/// `coordination_item.kind` (smallint). The wire value is [smallintValue];
/// GraphQL maps, activity encodings and SQL keep carrying the int.
enum CoordinationItemKind {
  plan(1),
  ask(2),
  blocker(3),
  promise(5),

  /// Request plan step («либретто», #220, m0250). Legacy kind 1 readers
  /// never see it.
  planStep(6),

  /// U088 — the Request's lobby: one row per Request whose id scopes the
  /// lobby discussion (`beacon_room_message.thread_item_id`).
  lobby(7);

  const CoordinationItemKind(this.smallintValue);

  final int smallintValue;

  /// `null` for a value no enum member carries (e.g. 4, or a kind added by a
  /// later server). Consumers treat it as "matches no known kind", which is
  /// what the int comparisons did.
  static CoordinationItemKind? fromSmallint(int? v) => switch (v) {
    1 => plan,
    2 => ask,
    3 => blocker,
    5 => promise,
    6 => planStep,
    7 => lobby,
    _ => null,
  };
}

/// `coordination_item.status` (smallint). Plan steps use [open] for a live
/// step and [cancelled] for a removed (soft-deleted) one.
enum CoordinationItemStatus {
  open(0),
  accepted(1),
  resolved(2),
  cancelled(3),
  superseded(4);

  const CoordinationItemStatus(this.smallintValue);

  final int smallintValue;

  /// `null` for a value no enum member carries; see
  /// [CoordinationItemKind.fromSmallint].
  static CoordinationItemStatus? fromSmallint(int? v) => switch (v) {
    0 => open,
    1 => accepted,
    2 => resolved,
    3 => cancelled,
    4 => superseded,
    _ => null,
  };
}

const int kCoordinationItemDefaultStaleDays = 3;
const int kCoordinationItemMaxStaleDays = 90;
const int kCoordinationItemRemindCooldownHours = 24;

// Coordination item event kind values (used in room_messages.linked_event_kind).
const int coordinationEventKindCreated = 1;
const int coordinationEventKindAccepted = 2;
const int coordinationEventKindResolved = 3;
const int coordinationEventKindCancelled = 4;
const int coordinationEventKindUpdated = 5;
const int coordinationEventKindSuperseded = 6;
