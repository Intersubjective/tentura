import 'package:tentura_server/domain/entity/gql_public/user_availability_record.dart';
import 'package:tentura_server/domain/entity/user_availability_entity.dart';

/// Public availability projection rules (V2 public user records): pure
/// entity -> record policy, independent of the storage layer.

/// Today's UTC calendar date (midnight UTC) used to judge pause expiry.
DateTime publicUserAvailabilityTodayUtc([DateTime? now]) {
  final instant = now ?? DateTime.timestamp();
  return DateTime.utc(
    instant.toUtc().year,
    instant.toUtc().month,
    instant.toUtc().day,
  );
}

/// Maps a stored row to the V2 public projection, suppressing expired pause-only rows.
UserAvailabilityRecord? userAvailabilityEntityToPublicRecord({
  required UserAvailabilityEntity? entity,
  required DateTime todayUtc,
}) {
  if (entity == null) {
    return null;
  }
  if (!entity.isLimited && entity.resumeOn != null) {
    if (!todayUtc.isBefore(entity.resumeOn!)) {
      return null;
    }
  }
  return UserAvailabilityRecord(
    isLimited: entity.isLimited,
    resumeOn: entity.resumeOn,
  );
}

String utcCalendarDateToWireString(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
