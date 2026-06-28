import 'package:freezed_annotation/freezed_annotation.dart';

part 'coordination_item.freezed.dart';

enum CoordinationItemKind {
  plan(1),
  ask(2),
  blocker(3),
  resolution(4),
  promise(5);

  const CoordinationItemKind(this.value);
  final int value;

  /// Ask, promise, and blocker items have directed source→target parties.
  bool get hasDirectedParties => switch (this) {
        CoordinationItemKind.ask ||
        CoordinationItemKind.promise ||
        CoordinationItemKind.blocker =>
          true,
        _ => false,
      };

  static CoordinationItemKind fromInt(int v) => switch (v) {
        1 => plan,
        2 => ask,
        3 => blocker,
        4 => resolution,
        5 => promise,
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

  static CoordinationItemEventKind? fromInt(int v) => switch (v) {
        1 => created,
        2 => accepted,
        3 => resolved,
        4 => cancelled,
        5 => updated,
        6 => superseded,
        _ => null,
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
    DateTime? lastRemindedAt,
    int? staleAfterDays,
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

  static const defaultStaleDays = 3;
  static const remindCooldownHours = 24;

  /// Derived stale state — must match server isItemStale rules.
  bool isStaleAt([DateTime? now]) {
    final at = staleAt;
    if (at == null || !isActive) return false;
    return !at.toUtc().isAfter((now ?? DateTime.now()).toUtc());
  }

  bool get isStale => isStaleAt();

  /// Elapsed time since [staleAt] when [isStaleAt]; null otherwise.
  Duration? staleOverdueDuration([DateTime? now]) {
    final at = staleAt;
    if (at == null || !isActive) return null;
    final n = (now ?? DateTime.now()).toUtc();
    final staleUtc = at.toUtc();
    if (staleUtc.isAfter(n)) return null;
    final overdue = n.difference(staleUtc);
    return overdue.isNegative ? Duration.zero : overdue;
  }

  /// When the stale overdue card label next changes; null when not applicable.
  DateTime? nextStaleOverdueLabelChangeAt([DateTime? now]) {
    if (!isActive) return null;
    final at = staleAt?.toUtc();
    if (at == null) return null;
    final n = (now ?? DateTime.now()).toUtc();
    if (at.isAfter(n)) return at;
    final overdue = n.difference(at);
    if (overdue.inDays >= 1) {
      return at.add(Duration(days: overdue.inDays + 1));
    }
    if (overdue.inHours >= 1) {
      return at.add(Duration(hours: overdue.inHours + 1));
    }
    return at.add(Duration(minutes: overdue.inMinutes + 1));
  }

  /// Minutes/hours/days value for the stale overdue card label.
  int? staleOverdueLabelAmount([DateTime? now]) {
    final overdue = staleOverdueDuration(now);
    if (overdue == null) return null;
    if (overdue.inDays >= 1) return overdue.inDays;
    if (overdue.inHours >= 1) return overdue.inHours;
    return overdue.inMinutes < 1 ? 1 : overdue.inMinutes;
  }

  bool isRemindInCooldown([DateTime? now]) {
    final last = lastRemindedAt;
    if (last == null) return false;
    final n = (now ?? DateTime.now()).toUtc();
    return last
        .toUtc()
        .isAfter(n.subtract(const Duration(hours: remindCooldownHours)));
  }

  /// Status-aware remind push recipient — mirrors server rules.
  String? get responsibleUserId {
    if (kind != CoordinationItemKind.ask &&
        kind != CoordinationItemKind.promise &&
        kind != CoordinationItemKind.blocker) {
      return null;
    }
    final target = targetPersonId?.trim();
    final hasTarget = target != null && target.isNotEmpty;

    return switch (kind) {
      CoordinationItemKind.ask => isAccepted
          ? ((acceptedById?.trim().isNotEmpty ?? false)
              ? acceptedById!.trim()
              : (hasTarget ? target : null))
          : (hasTarget ? target : null),
      CoordinationItemKind.promise => isOpen
          ? (hasTarget ? target : null)
          : isAccepted
              ? creatorId
              : null,
      CoordinationItemKind.blocker =>
        hasTarget ? target : creatorId,
      _ => null,
    };
  }

  bool canRemind(String viewerId) =>
      isStale &&
      isActive &&
      responsibleUserId != null &&
      responsibleUserId != viewerId &&
      !isRemindInCooldown();

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

  /// Viewer is source ([creatorId]) or target ([targetPersonId]) on ask/promise/blocker.
  bool directInvolvementAsSourceOrTarget(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) return false;
    if (kind == CoordinationItemKind.plan ||
        kind == CoordinationItemKind.resolution) {
      return false;
    }
    if (creatorId.trim() == uid) return true;
    final target = targetPersonId?.trim();
    return target != null && target.isNotEmpty && target == uid;
  }

  /// Active-fold "for me" filter — source/target on ask/promise/blocker, plus
  /// resolutions linked to a directly involved parent (one hop).
  bool involvesUserAsSourceOrTarget(
    String userId, {
    CoordinationItem? resolutionParent,
  }) {
    final uid = userId.trim();
    if (uid.isEmpty) return false;

    if (kind == CoordinationItemKind.plan) return false;

    if (kind == CoordinationItemKind.resolution) {
      if (creatorId.trim() == uid) return true;
      final target = targetPersonId?.trim();
      if (target != null && target.isNotEmpty && target == uid) return true;
      final parentId = targetItemId?.trim();
      if (parentId == null || parentId.isEmpty) return false;
      final parent = resolutionParent;
      if (parent == null || parent.id != parentId) return false;
      return parent.directInvolvementAsSourceOrTarget(uid);
    }

    return directInvolvementAsSourceOrTarget(uid);
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

/// Filters active open items to those involving [userId] as source or target.
List<CoordinationItem> filterActiveItemsForUser({
  required List<CoordinationItem> openItems,
  required Iterable<CoordinationItem> lookupItems,
  required String userId,
  required bool forMeOnly,
  String? alwaysIncludeItemId,
}) {
  if (!forMeOnly) return openItems;

  final byId = <String, CoordinationItem>{
    for (final item in lookupItems)
      if (item.kind != CoordinationItemKind.plan) item.id: item,
  };

  final focusId = alwaysIncludeItemId?.trim();
  final hasFocusBypass = focusId != null && focusId.isNotEmpty;

  return openItems.where((item) {
    if (hasFocusBypass && item.id == focusId) return true;
    return item.involvesUserAsSourceOrTarget(
      userId,
      resolutionParent: item.targetItemId != null
          ? byId[item.targetItemId]
          : null,
    );
  }).toList();
}
