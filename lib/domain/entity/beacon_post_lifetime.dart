import 'beacon_status.dart';

/// Lifetime rules for a Post (`beacon.kind = 1`); Requests never expire.
abstract final class BeaconPostLifetime {
  static const minHours = 1;

  static const maxHours = 72;

  static const max = Duration(hours: maxHours);

  static const warnBefore = Duration(hours: 3);

  static const _kindPost = 1;

  /// An open Post whose `expires_at` has been reached. Closed is closed, not
  /// expired.
  static bool isExpired({
    required int kind,
    required BeaconStatus status,
    required DateTime? expiresAt,
    required DateTime now,
  }) =>
      kind == _kindPost &&
      status == BeaconStatus.open &&
      expiresAt != null &&
      !expiresAt.isAfter(now);
}
