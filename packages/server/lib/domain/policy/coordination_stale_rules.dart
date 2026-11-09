import 'package:tentura_server/consts/coordination_item_consts.dart';

/// Minimal item slice for pure staleness / remind rules (no DB types).
final class CoordinationStaleItemView {
  const CoordinationStaleItemView({
    required this.kind,
    required this.status,
    required this.creatorId,
    this.targetPersonId,
    this.acceptedById,
    this.staleAt,
    this.staleAfterDays,
  });

  /// `null` when the stored smallint is not a known kind/status; it then
  /// matches no rule (not stale, no responsible user).
  final CoordinationItemKind? kind;
  final CoordinationItemStatus? status;
  final String creatorId;
  final String? targetPersonId;
  final String? acceptedById;
  final DateTime? staleAt;
  final int? staleAfterDays;
}

/// Resolves GraphQL/client input: omitted → default 3; 0 → no deadline; 1–90 → days.
int validateStaleAfterDays(int? input) {
  if (input == null) {
    return kCoordinationItemDefaultStaleDays;
  }
  if (input == 0) {
    return 0;
  }
  if (input < 0 || input > kCoordinationItemMaxStaleDays) {
    throw ArgumentError.value(
      input,
      'staleAfterDays',
      'Must be 0 (no deadline) or 1–$kCoordinationItemMaxStaleDays',
    );
  }
  return input;
}

/// [staleAfterDays] must already be validated (0 = no deadline).
DateTime? computeStaleAt(DateTime publishTime, int staleAfterDays) {
  if (staleAfterDays == 0) {
    return null;
  }
  return publishTime.add(Duration(days: staleAfterDays));
}

bool isItemStale(CoordinationStaleItemView item, DateTime nowUtc) {
  final staleAt = item.staleAt;
  if (staleAt == null) {
    return false;
  }
  if (item.status != CoordinationItemStatus.open &&
      item.status != CoordinationItemStatus.accepted) {
    return false;
  }
  return !staleAt.isAfter(nowUtc);
}

bool isRemindableKind(CoordinationItemKind? kind) =>
    kind == CoordinationItemKind.plan;

/// Status-aware responsible person for remind push.
String? resolveResponsibleUserId(CoordinationStaleItemView item) {
  if (!isRemindableKind(item.kind)) {
    return null;
  }
  final target = item.targetPersonId?.trim();
  final hasTarget = target != null && target.isNotEmpty;

  switch (item.kind) {
    case CoordinationItemKind.plan:
      if (item.status != CoordinationItemStatus.open &&
          item.status != CoordinationItemStatus.accepted) {
        return null;
      }
      return hasTarget ? target : item.creatorId;

    case CoordinationItemKind.ask:
      if (item.status == CoordinationItemStatus.accepted) {
        final accepted = item.acceptedById?.trim();
        if (accepted != null && accepted.isNotEmpty) {
          return accepted;
        }
      }
      return hasTarget ? target : null;

    case CoordinationItemKind.promise:
      if (item.status == CoordinationItemStatus.open) {
        return hasTarget ? target : null;
      }
      if (item.status == CoordinationItemStatus.accepted) {
        return item.creatorId;
      }
      return null;

    case CoordinationItemKind.blocker:
      if (hasTarget) {
        return target;
      }
      return item.creatorId;

    case CoordinationItemKind.planStep || CoordinationItemKind.lobby || null:
      return null;
  }
}

/// Recompute deadline after accept from stored window.
DateTime? computeStaleAtAfterAccept({
  required DateTime nowUtc,
  required int? staleAfterDays,
}) {
  final days = staleAfterDays ?? kCoordinationItemDefaultStaleDays;
  return computeStaleAt(nowUtc, days);
}
