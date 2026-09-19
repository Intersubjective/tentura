import 'dart:convert';

/// Parsed `inbox_item.inbox_provenance_data` (JSON string from Hasura computed field).
class InboxProvenance {
  const InboxProvenance({
    required this.senders,
    required this.totalDistinctSenders,
    required this.strongestNotePreview,
    this.latestNoteForward,
  });

  final List<InboxForwardSender> senders;
  final int totalDistinctSenders;
  final String strongestNotePreview;

  /// The latest forward carrying a note (D-171-5a), or `null` when nobody
  /// wrote anything.
  ///
  /// [senders] is a MeritRank-ranked window and [strongestNotePreview] is read
  /// off its top entry, so neither can answer "which note is newest" — the
  /// note in question may belong to a sender the window never reached. The
  /// server selects this one explicitly, under the same filters as the list
  /// and the count.
  final InboxLatestNoteForward? latestNoteForward;

  static const empty = InboxProvenance(
    senders: [],
    totalDistinctSenders: 0,
    strongestNotePreview: '',
  );

  factory InboxProvenance.parse(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>?;
      if (map == null) return empty;
      final sendersJson = map['senders'];
      final senders = <InboxForwardSender>[];
      if (sendersJson is List<dynamic>) {
        for (final e in sendersJson) {
          if (e is! Map<String, dynamic>) continue;
          final id = e['id'] as String? ?? '';
          if (id.isEmpty) continue;
          final mr = e['mr'];
          final rawSlugs = e['reasonSlugs'];
          final reasonSlugs = rawSlugs is List
              ? rawSlugs.whereType<String>().toList()
              : const <String>[];
          senders.add(
            InboxForwardSender(
              id: id,
              displayName: e['displayName'] as String? ?? '',
              mr: mr is num ? mr.toDouble() : double.tryParse('$mr') ?? 0,
              imageId: e['imageId'] as String?,
              notePreview: e['notePreview'] as String? ?? '',
              reasonSlugs: reasonSlugs,
            ),
          );
        }
      }
      final total = map['totalDistinctSenders'];
      final note = map['strongestNotePreview'] as String? ?? '';
      return InboxProvenance(
        senders: senders,
        totalDistinctSenders: total is int
            ? total
            : int.tryParse('$total') ?? 0,
        strongestNotePreview: note,
        latestNoteForward: InboxLatestNoteForward._parse(
          map['latestNoteForward'],
        ),
      );
    } on Object {
      return empty;
    }
  }

  /// Drops the viewer from forwarder attribution (never show self as forwarder).
  InboxProvenance withoutViewer(String viewerId) {
    if (viewerId.isEmpty) return this;
    final filtered = senders
        .where((s) => s.id.isNotEmpty && s.id != viewerId)
        .toList();
    // The pinned forward obeys the same rule as the list — never show self as
    // forwarder — so it drops even when the list itself needs no change.
    final pinned = latestNoteForward?.senderId == viewerId
        ? null
        : latestNoteForward;
    if (filtered.length == senders.length &&
        identical(pinned, latestNoteForward)) {
      return this;
    }
    final removed = senders.length - filtered.length;
    final adjustedTotal = totalDistinctSenders - removed;
    return InboxProvenance(
      senders: filtered,
      totalDistinctSenders: adjustedTotal < 0 ? 0 : adjustedTotal,
      strongestNotePreview: strongestNotePreview,
      latestNoteForward: pinned,
    );
  }
}

/// The forward the card pins to its first collapsed slot (card spec §7.1,
/// D-171-5a): the latest one carrying a note, with the identity and the time
/// the mini-card needs to render and open it.
class InboxLatestNoteForward {
  const InboxLatestNoteForward({
    required this.forwardId,
    required this.senderId,
    required this.displayName,
    required this.notePreview,
    this.imageId,
    this.forwardedAt,
    this.reasonSlugs = const [],
  });

  static InboxLatestNoteForward? _parse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final forwardId = raw['forwardId'] as String? ?? '';
    final senderId = raw['senderId'] as String? ?? '';
    final notePreview = raw['notePreview'] as String? ?? '';
    if (forwardId.isEmpty || senderId.isEmpty || notePreview.isEmpty) {
      return null;
    }
    final slugs = raw['reasonSlugs'];
    return InboxLatestNoteForward(
      forwardId: forwardId,
      senderId: senderId,
      displayName: raw['displayName'] as String? ?? '',
      notePreview: notePreview,
      imageId: raw['imageId'] as String?,
      forwardedAt: DateTime.tryParse(
        raw['forwardedAt'] as String? ?? '',
      )?.toUtc(),
      reasonSlugs: slugs is List
          ? slugs.whereType<String>().toList()
          : const <String>[],
    );
  }

  final String forwardId;
  final String senderId;
  final String displayName;
  final String? imageId;

  /// Non-empty by construction — a note-less forward is not a candidate.
  final String notePreview;

  /// When the forward was made, for the mini-card's «<age>» (§7).
  final DateTime? forwardedAt;

  /// Capability slugs this forwarder assigned — the chips belong to them.
  final List<String> reasonSlugs;
}

class InboxForwardSender {
  const InboxForwardSender({
    required this.id,
    required this.displayName,
    required this.mr,
    this.imageId,
    this.notePreview = '',
    this.reasonSlugs = const [],
  });

  final String id;
  final String displayName;
  final double mr;
  final String? imageId;

  /// Latest forward note from this sender to the viewer (trimmed server-side).
  final String notePreview;

  /// Capability slugs the sender assigned when forwarding to the viewer.
  final List<String> reasonSlugs;
}
