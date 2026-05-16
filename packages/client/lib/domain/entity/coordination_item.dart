import 'package:freezed_annotation/freezed_annotation.dart';

part 'coordination_item.freezed.dart';

enum CoordinationItemKind {
  plan(1),
  ask(2),
  blocker(3),
  resolution(4);

  const CoordinationItemKind(this.value);
  final int value;

  static CoordinationItemKind fromInt(int v) => switch (v) {
        1 => plan,
        2 => ask,
        3 => blocker,
        4 => resolution,
        _ => throw ArgumentError.value(v, 'kind'),
      };
}

enum CoordinationItemStatus {
  open(0),
  accepted(1),
  resolved(2),
  cancelled(3),
  superseded(4);

  const CoordinationItemStatus(this.value);
  final int value;

  static CoordinationItemStatus fromInt(int v) => switch (v) {
        0 => open,
        1 => accepted,
        2 => resolved,
        3 => cancelled,
        4 => superseded,
        _ => throw ArgumentError.value(v, 'status'),
      };
}

enum CoordinationItemEventKind {
  created(1),
  accepted(2),
  resolved(3),
  cancelled(4),
  updated(5),
  superseded(6);

  const CoordinationItemEventKind(this.value);
  final int value;

  static CoordinationItemEventKind fromInt(int v) => switch (v) {
        1 => created,
        2 => accepted,
        3 => resolved,
        4 => cancelled,
        5 => updated,
        6 => superseded,
        _ => throw ArgumentError.value(v, 'eventKind'),
      };
}

@freezed
abstract class CoordinationItem with _$CoordinationItem {
  const factory CoordinationItem({
    required String id,
    required String beaconId,
    required CoordinationItemKind kind,
    required CoordinationItemStatus status,
    required String creatorId,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(0) int source,
    @Default(true) bool published,
    @Default('') String title,
    @Default('') String body,
    String? targetPersonId,
    String? acceptedById,
    String? targetItemId,
    String? targetMessageId,
    String? linkedMessageId,
    String? linkedParentItemId,
    DateTime? resolvedAt,
    DateTime? cancelledAt,
    DateTime? staleAt,
    @Default(0) int messageCount,
    @Default(0) int unreadCount,
    DateTime? lastSeenAt,
  }) = _CoordinationItem;

  const CoordinationItem._();

  bool get hasUnread => unreadCount > 0;

  bool get isOpen => status == CoordinationItemStatus.open;
  bool get isAccepted => status == CoordinationItemStatus.accepted;
  bool get isResolved => status == CoordinationItemStatus.resolved;
  bool get isCancelled => status == CoordinationItemStatus.cancelled;
  bool get isSuperseded => status == CoordinationItemStatus.superseded;

  bool get isRootPlan =>
      kind == CoordinationItemKind.plan && linkedParentItemId == null;

  bool get isPlanStep =>
      kind == CoordinationItemKind.plan && linkedParentItemId != null;

  /// Open or accepted — still active on the Items tab.
  bool get isActive =>
      isOpen || isAccepted;

  /// Primary text for list cards: [body] when set, otherwise [title].
  String get contentPreview {
    final trimmedBody = body.trim();
    if (trimmedBody.isNotEmpty) return trimmedBody;
    return title.trim();
  }

  /// Room message id to scroll to when opening this item’s thread, when known.
  String? get threadAnchorMessageId {
    for (final candidate in [linkedMessageId, targetMessageId]) {
      if (candidate == null) continue;
      final t = candidate.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  static final empty = CoordinationItem(
    id: '',
    beaconId: '',
    kind: CoordinationItemKind.blocker,
    status: CoordinationItemStatus.open,
    creatorId: '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}
