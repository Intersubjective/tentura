import 'package:built_value/serializer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/data/gql/calendar_date_serializer.dart';

const _expectNonUtcOffset = bool.fromEnvironment('availability_expect_non_utc');

void main() {
  final serializer = CalendarDateSerializer();
  final serializers = Serializers();
  const wire = '2026-08-18';

  group('CalendarDateSerializer', () {
    test('round-trips UTC calendar date unchanged', () {
      final parsed = serializer.deserialize(serializers, wire);
      expect(parsed, DateTime.utc(2026, 8, 18));
      expect(serializer.serialize(serializers, parsed), wire);
    });

    test('round-trips unchanged under a non-UTC process/browser timezone', () {
      if (_expectNonUtcOffset) {
        expect(
          DateTime.now().timeZoneOffset,
          isNot(Duration.zero),
          reason:
              'Set TZ to a non-UTC zone and pass '
              '--dart-define=availability_expect_non_utc=true',
        );
      }
      final parsed = serializer.deserialize(serializers, wire);
      expect(parsed.isUtc, isTrue);
      expect(parsed, DateTime.utc(2026, 8, 18));
      expect(serializer.serialize(serializers, parsed), wire);
    });

    test('rejects non-midnight serialization', () {
      expect(
        () => serializer.serialize(serializers, DateTime.utc(2026, 8, 18, 12)),
        throwsFormatException,
      );
    });

    test('rejects malformed wire strings on deserialize', () {
      expect(
        () => serializer.deserialize(serializers, '2026-08-18T00:00:00Z'),
        throwsFormatException,
      );
    });

    test('rejects non-string wire on deserialize', () {
      expect(
        () => serializer.deserialize(serializers, 20260818),
        throwsFormatException,
      );
    });

    test('rejects calendar overflow on deserialize', () {
      expect(
        () => serializer.deserialize(serializers, '2026-02-31'),
        throwsFormatException,
      );
      expect(
        () => parseStrictUtcCalendarDateString('2026-02-31'),
        throwsFormatException,
      );
    });
  });
}
