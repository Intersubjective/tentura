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
/// totals, and a child read optimistically moves the unseen count with it.
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
  final rawUnseen = eventsPreview.where((child) => !child.isSeen).length;
  final keptUnseen = kept.where((child) => !child.isSeen).length;
  if (dismissed == 0 && rawUnseen == keptUnseen) {
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
  final unseenCount = (eventUnseenCount - (rawUnseen - keptUnseen)).clamp(
    0,
    total,
  );
  return AttentionGroupProjection(
    eventTotal: total,
    eventUnseenCount: unseenCount,
    eventsPreview: kept,
    unseen: unseenCount > 0,
  );
}
