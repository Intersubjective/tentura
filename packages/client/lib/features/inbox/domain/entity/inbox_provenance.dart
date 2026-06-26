import 'dart:convert';

/// Parsed `inbox_item.inbox_provenance_data` (JSON string from Hasura computed field).
class InboxProvenance {
  const InboxProvenance({
    required this.senders,
    required this.totalDistinctSenders,
    required this.strongestNotePreview,
  });

  final List<InboxForwardSender> senders;
  final int totalDistinctSenders;
  final String strongestNotePreview;

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
    if (filtered.length == senders.length) return this;
    final removed = senders.length - filtered.length;
    final adjustedTotal = totalDistinctSenders - removed;
    return InboxProvenance(
      senders: filtered,
      totalDistinctSenders: adjustedTotal < 0 ? 0 : adjustedTotal,
      strongestNotePreview: strongestNotePreview,
    );
  }
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
