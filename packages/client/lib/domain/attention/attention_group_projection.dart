import 'dart:math' as math;

import 'entity/attention_receipt.dart';

/// One grouped row's preview and counts, re-derived from its children.
final class AttentionGroupProjection {
  const AttentionGroupProjection({
    required this.eventTotal,
    required this.eventUnseenCount,
    required this.eventsPreview,
    required this.unseen,
  });

  final int eventTotal;
  final int eventUnseenCount;
  final List<AttentionReceipt> eventsPreview;
  final bool unseen;
}

/// Re-projects a grouped row against the local clear/ack overlays.
///
/// The card and its counts are **one** projection, not two. Dropping a
/// dismissed child from the preview while leaving `eventTotal` where the
/// server last put it is the failure U10b described: the list looks right and
/// the number beside it lies. So every removal moves the preview *and* the
/// totals.
///
/// What does **not** move them is reading (R2/D02). The server defines
/// `eventUnseenCount` as `COUNT(*) FILTER (WHERE NOT requires_action AND
/// cleared_at IS NULL)` — despite the name, `seen_at` is not in it. Until
/// U15R-c a child marked seen optimistically took one off the count, so the
/// dot went out over children the server was still counting.
///
/// [overlay] is the caller's local view of one child — clear overlay first,
/// then read acks — so this function never needs to know the stores exist.
AttentionGroupProjection projectAttentionGroup({
  required int eventTotal,
  required int eventUnseenCount,
  required List<AttentionReceipt> eventsPreview,
  required bool unseen,
  required AttentionReceipt Function(AttentionReceipt child) overlay,
}) {
  if (eventsPreview.isEmpty) {
    return AttentionGroupProjection(
      eventTotal: eventTotal,
      eventUnseenCount: eventUnseenCount,
      eventsPreview: eventsPreview,
      unseen: unseen,
    );
  }
  final overlaid = [for (final child in eventsPreview) overlay(child)];
  final kept = [
    for (final child in overlaid)
      if (!child.isCleared) child,
  ];
  final dismissed = overlaid.length - kept.length;
  if (dismissed == 0) {
    // Nothing local applies; keep the server's numbers verbatim rather than
    // recomputing them from a preview that is only the first few children.
    return AttentionGroupProjection(
      eventTotal: eventTotal,
      eventUnseenCount: eventUnseenCount,
      eventsPreview: overlaid,
      unseen: unseen,
    );
  }
  final total = math.max(0, eventTotal - dismissed);
  // Only cleared children leave the count, and each one takes exactly one
  // with it — the same arithmetic the server does over the same predicate.
  final unseenCount = (eventUnseenCount - dismissed).clamp(0, total);
  return AttentionGroupProjection(
    eventTotal: total,
    eventUnseenCount: unseenCount,
    eventsPreview: kept,
    unseen: unseenCount > 0,
  );
}
