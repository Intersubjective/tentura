import 'package:meta/meta.dart';

/// Matches Hasura `user_presence` for merged `v2_user`.
@immutable
class UserPresenceRecord {
  const UserPresenceRecord({
    required this.lastSeenAt,
    required this.status,
  });

  final DateTime lastSeenAt;
  final int status;
}
