import 'package:built_value/serializer.dart';

/// Strict UTC calendar-date wire format (`YYYY-MM-DD`) for Hasura `date`.
class CalendarDateSerializer implements PrimitiveSerializer<DateTime> {
  static final RegExp _wirePattern = RegExp(
    r'^(?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2})$',
  );

  @override
  DateTime deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    if (serialized is! String) {
      throw FormatException(
        'CalendarDateSerializer: expected YYYY-MM-DD string, got $serialized',
      );
    }
    return parseStrictUtcCalendarDateString(serialized);
  }

  @override
  Object serialize(
    Serializers serializers,
    DateTime date, {
    FullType specifiedType = FullType.unspecified,
  }) {
    if (!date.isUtc ||
        date.hour != 0 ||
        date.minute != 0 ||
        date.second != 0 ||
        date.millisecond != 0 ||
        date.microsecond != 0) {
      throw FormatException(
        'CalendarDateSerializer: expected UTC midnight, got $date',
      );
    }
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Iterable<Type> get types => [DateTime];

  @override
  String get wireName => 'date';
}

/// Parses [wire] as a strict UTC calendar date (`YYYY-MM-DD` at midnight).
///
/// Rejects malformed strings, non-calendar month/day values, overflow dates
/// (e.g. `2026-02-31`), and any value that would normalize to a different
/// calendar day.
DateTime parseStrictUtcCalendarDateString(String wire) {
  final match = CalendarDateSerializer._wirePattern.firstMatch(wire);
  if (match == null) {
    throw FormatException(
      'parseStrictUtcCalendarDateString: expected YYYY-MM-DD, got $wire',
    );
  }
  final year = int.parse(match.namedGroup('y')!);
  final month = int.parse(match.namedGroup('m')!);
  final day = int.parse(match.namedGroup('d')!);
  if (month < 1 || month > 12) {
    throw FormatException(
      'parseStrictUtcCalendarDateString: invalid month $month in $wire',
    );
  }
  final maxDay = _daysInMonth(year, month);
  if (day < 1 || day > maxDay) {
    throw FormatException(
      'parseStrictUtcCalendarDateString: invalid day $day in $wire',
    );
  }
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw FormatException(
      'parseStrictUtcCalendarDateString: calendar overflow in $wire',
    );
  }
  return parsed;
}

int _daysInMonth(int year, int month) {
  switch (month) {
    case 2:
      final leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
      return leap ? 29 : 28;
    case 4:
    case 6:
    case 9:
    case 11:
      return 30;
    default:
      return 31;
  }
}
