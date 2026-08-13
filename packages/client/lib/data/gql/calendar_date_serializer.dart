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
    final match = _wirePattern.firstMatch(serialized as String);
    if (match == null) {
      throw FormatException(
        'CalendarDateSerializer: expected YYYY-MM-DD, got $serialized',
      );
    }
    final year = int.parse(match.namedGroup('y')!);
    final month = int.parse(match.namedGroup('m')!);
    final day = int.parse(match.namedGroup('d')!);
    return DateTime.utc(year, month, day);
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
