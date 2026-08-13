part of '_input_types.dart';

final _calendarDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Strict ISO calendar-date parser: canonical `YYYY-MM-DD` only.
DateTime parseCalendarDate(String value, {String fieldName = 'resumeOn'}) {
  if (!_calendarDatePattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      fieldName,
      'must be a canonical ISO calendar date YYYY-MM-DD',
    );
  }

  final parts = value.split('-');
  final year = int.parse(parts[0]);
  final month = int.parse(parts[1]);
  final day = int.parse(parts[2]);

  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw ArgumentError.value(
      value,
      fieldName,
      'is not a valid calendar date',
    );
  }

  return date;
}

class InputFieldCalendarDate {
  InputFieldCalendarDate({required String fieldName})
    : field = GraphQLFieldInput(fieldName, graphQLString.nonNullable());

  final GraphQLFieldInput<String, String> field;

  DateTime fromArgsNonNullable(Map<String, dynamic> args) {
    final raw = args[field.name];
    if (raw is! String) {
      throw ArgumentError.value(
        raw,
        field.name,
        'required calendar date argument is missing or invalid',
      );
    }
    return parseCalendarDate(raw, fieldName: field.name);
  }
}
