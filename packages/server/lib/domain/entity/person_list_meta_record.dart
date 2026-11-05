import 'package:meta/meta.dart';

/// Why a person is in the People list's "New" section.
enum PersonNewReason { invite, trusted, mutual }

/// Sort keys for one person the viewer trusts, for the People tab.
@immutable
class PersonListMetaRecord {
  const PersonListMetaRecord({
    required this.id,
    this.newSince,
    this.newReason,
    this.lastInteractionAt,
  });

  final String id;

  /// When the relationship started, only if that is within the last 7 days.
  final DateTime? newSince;

  /// What produced [newSince]; null exactly when [newSince] is null.
  final PersonNewReason? newReason;

  /// Latest forward, room message, trust change or invite acceptance between
  /// the viewer and this person; null if none.
  final DateTime? lastInteractionAt;
}
