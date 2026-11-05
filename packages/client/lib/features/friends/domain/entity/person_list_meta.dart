import 'package:meta/meta.dart';

/// Why a person appears in the People tab «New» section (#912).
enum PersonNewReason { invite, trusted, mutual }

/// Sort keys for one trusted person on the People tab (V2 peopleListMeta query).
@immutable
class PersonListMeta {
  const PersonListMeta({
    required this.id,
    this.newSince,
    this.newReason,
    this.lastInteractionAt,
  });

  final String id;
  final DateTime? newSince;
  final PersonNewReason? newReason;
  final DateTime? lastInteractionAt;

  bool get isNew => newSince != null;

  static PersonNewReason? reasonFromWire(String? value) => switch (value) {
    'invite' => PersonNewReason.invite,
    'trusted' => PersonNewReason.trusted,
    'mutual' => PersonNewReason.mutual,
    _ => null,
  };

  PersonListMeta mergedWith(PersonListMeta? other) {
    if (other == null) return this;
    if (other.newSince == null) return this;
    if (newSince == null) return other;
    return other.newSince!.isAfter(newSince!) ? other : this;
  }
}
