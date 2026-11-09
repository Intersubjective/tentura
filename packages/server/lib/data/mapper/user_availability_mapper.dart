import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/user_availability_entity.dart';

import '../database/tentura_db.dart';

UserAvailabilityEntity userAvailabilityModelToEntity(
  UserAvailabilityData model,
) =>
    UserAvailabilityEntity(
      userId: model.userId,
      isLimited: model.isLimited,
      resumeOn: _resumeOnToUtcCalendar(model.resumeOn),
    );

DateTime? _resumeOnToUtcCalendar(PgDate? value) {
  if (value == null) {
    return null;
  }
  return DateTime.utc(value.year, value.month, value.day);
}
