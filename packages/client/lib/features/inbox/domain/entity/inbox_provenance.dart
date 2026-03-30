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

  static InboxProvenance parse(String? raw) {
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
          senders.add(
            InboxForwardSender(
              id: id,
              title: e['title'] as String? ?? '',
              mr: mr is num ? mr.toDouble() : double.tryParse('$mr') ?? 0,
              imageId: e['imageId'] as String?,
            ),
          );
        }
      }
      final total = map['totalDistinctSenders'];
      final note = map['strongestNotePreview'] as String? ?? '';
      return InboxProvenance(
        senders: senders,
        totalDistinctSenders: total is int ? total : int.tryParse('$total') ?? 0,
        strongestNotePreview: note,
      );
    } on Object {
      return empty;
    }
  }
}

class InboxForwardSender {
  const InboxForwardSender({
    required this.id,
    required this.title,
    required this.mr,
    this.imageId,
  });

  final String id;
  final String title;
  final double mr;
  final String? imageId;
}
