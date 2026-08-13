import 'package:meta/meta.dart';

/// Matches Hasura `user_availability` for merged `v2_user`.
@immutable
class UserAvailabilityRecord {
  const UserAvailabilityRecord({
    required this.isLimited,
    this.resumeOn,
  });

  final bool isLimited;

  /// UTC-midnight calendar date; never localized on the wire.
  final DateTime? resumeOn;
}
