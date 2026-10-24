import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/person_auto_tag_kind.dart';

void main() {
  group('PersonAutoTagKind wire values', () {
    test('are stable smallints shared by the server and the client', () {
      expect(
        {for (final k in PersonAutoTagKind.values) k.name: k.smallintValue},
        {
          'mutualContact': 0,
          'iTrust': 1,
          'trustsMe': 2,
          'helpedMe': 3,
          'iHelped': 4,
          'workedTogether': 5,
          'invited': 6,
          'forwarded': 7,
          'newOnField': 8,
        },
      );
    });

    test('fromSmallint round-trips every kind', () {
      for (final k in PersonAutoTagKind.values) {
        expect(PersonAutoTagKind.fromSmallint(k.smallintValue), k);
      }
    });

    test('fromSmallint rejects an unknown value', () {
      expect(() => PersonAutoTagKind.fromSmallint(99), throwsA(anything));
    });

    test('filter-row defaults follow the product table', () {
      expect(
        {
          for (final k in PersonAutoTagKind.values)
            k.name: k.defaultShowInFilters,
        },
        {
          'mutualContact': true,
          'iTrust': true,
          'trustsMe': false,
          'helpedMe': true,
          'iHelped': true,
          'workedTogether': true,
          'invited': false,
          'forwarded': false,
          'newOnField': true,
        },
      );
    });
  });
}
