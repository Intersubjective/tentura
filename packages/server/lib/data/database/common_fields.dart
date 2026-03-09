import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts.dart';

mixin TitleDescriptionFields on Table {
  late final title = text().withLength(
    min: kTitleMinLength,
    max: kTitleMaxLength,
  )();

  late final description = text()
      .withLength(max: kDescriptionMaxLength)
      .withDefault(const Constant(''))();
}

mixin TimestampsFields on Table {
  late final createdAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();

  late final updatedAt = customType(
    PgTypes.timestampWithTimezone,
  ).clientDefault(() => PgDateTime(DateTime.timestamp()))();
}

mixin TickerFields on Table {
  late final Column<int> ticker = integer()
      .check(ticker.isBiggerOrEqualValue(0))
      .withDefault(const Constant(0))();
}
