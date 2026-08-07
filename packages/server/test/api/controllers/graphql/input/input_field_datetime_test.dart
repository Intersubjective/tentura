import 'package:test/test.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';

void main() {
  group('InputFieldDatetime', () {
    final field = InputFieldDatetime(fieldName: 'startAt');

    test('Z-suffixed input parses as UTC, instant unchanged', () {
      final result = field.fromArgs({'startAt': '2026-08-10T14:30:00.000Z'});
      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result, DateTime.utc(2026, 8, 10, 14, 30));
    });

    test('offset-less input is treated as UTC digits, not server-local', () {
      final result = field.fromArgs({'startAt': '2026-08-10T00:00:00.000'});
      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result, DateTime.utc(2026, 8, 10));
    });

    test('empty/absent input is null', () {
      expect(field.fromArgs({'startAt': ''}), isNull);
      expect(field.fromArgs({}), isNull);
    });

    test('fromArgsNonNullable also forces UTC', () {
      final result = field.fromArgsNonNullable({
        'startAt': '2026-08-10T00:00:00.000',
      });
      expect(result.isUtc, isTrue);
    });
  });
}
