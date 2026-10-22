import 'entity/forward_edge.dart';

/// The viewer's forward trail on one Request: how the Request reached the
/// viewer and whom the viewer sent it to (#396, #496).
///
/// This is the one client-side derivation People › Forwards renders and the
/// helper card's "Forwarded by you" claim is checked against. It is history,
/// not current membership: a recipient who offered help, was admitted,
/// withdrew or declined keeps their row; only the row's state changes.
///
/// * Outgoing edges stay even when cancelled (marked cancelled by the row):
///   cancellation is not deletion.
/// * Inbound cancelled edges are dropped: the sender took the forward back
///   (or a block cancelled it), so it is not how the Request reached the
///   viewer.
/// * One row per direction and counterpart, newest first; a live edge wins
///   over a cancelled one to the same person.
List<ForwardEdge> viewerForwardTrail(
  Iterable<ForwardEdge> edges, {
  required String viewerUserId,
}) {
  final sorted = [
    for (final e in edges)
      if (e.sender.id == viewerUserId ||
          (e.recipient.id == viewerUserId && !e.isCancelled))
        e,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  final byKey = <(bool, String), ForwardEdge>{};
  for (final e in sorted) {
    final outgoing = e.sender.id == viewerUserId;
    final key = (outgoing, outgoing ? e.recipient.id : e.sender.id);
    final kept = byKey[key];
    if (kept == null || (kept.isCancelled && !e.isCancelled)) {
      byKey[key] = e;
    }
  }
  final keep = byKey.values.toSet();
  return [
    for (final e in sorted)
      if (keep.contains(e)) e,
  ];
}

/// Whether [trail] holds a live (not cancelled) forward from [senderId] to
/// [recipientId].
bool trailHasLiveForward(
  Iterable<ForwardEdge> trail, {
  required String senderId,
  required String recipientId,
}) => trail.any(
  (e) =>
      !e.isCancelled &&
      e.sender.id == senderId &&
      e.recipient.id == recipientId,
);
