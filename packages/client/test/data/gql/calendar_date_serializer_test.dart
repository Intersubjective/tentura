import 'dart:io';

import 'package:built_value/serializer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/data/gql/calendar_date_serializer.dart';

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
      if (!kIsWeb) {
        final tz = Platform.environment['TZ'];
        if (tz != null && tz.isNotEmpty && tz != 'UTC') {
          expect(DateTime.now().timeZoneOffset, isNot(Duration.zero));
        }
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
  });
}
