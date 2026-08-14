import 'package:built_value/serializer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/gql/_g/serializers.gql.dart';
import 'package:tentura/data/gql/calendar_date_serializer.dart';
import 'package:tentura/data/gql/timestamptz_serializer.dart';

void main() {
  // Regression guard for the My Work infinite-spinner root cause: built_value's
  // Serializers registry keys custom PrimitiveSerializers by Dart *type*, not
  // by GraphQL scalar name (Serializers.deserialize dispatches on
  // FullType(DateTime) alone). Registering two PrimitiveSerializer<DateTime>
  // implementations — TimestamptzSerializer for `timestamptz` fields and
  // CalendarDateSerializer for the calendar-only `date` scalar — means
  // whichever is added to build.yaml's custom_serializers list last silently
  // wins the DateTime slot for every field in the app. When CalendarDateSerializer
  // won, every `timestamptz` field (created_at, updated_at, user_presence
  // .last_seen_at, ...) started throwing FormatException on deserialize,
  // which was swallowed inside Ferry's response stream instead of surfacing —
  // hanging the caller instead of failing visibly.
  group('DateTime serializer registration (My Work spinner regression)', () {
    test(
      'TimestamptzSerializer, not CalendarDateSerializer, owns DateTime',
      () {
        final serializer = serializers.serializerForType(DateTime);
        expect(serializer, isA<TimestamptzSerializer>());
        expect(serializer, isNot(isA<CalendarDateSerializer>()));
      },
    );

    test('a real timestamptz value deserializes instead of throwing', () {
      const wire = '2026-08-14T14:39:57.420841+00:00';
      final result = serializers.deserialize(
        wire,
        specifiedType: const FullType(DateTime),
      );
      expect(result, DateTime.parse(wire));
    });
  });
}
