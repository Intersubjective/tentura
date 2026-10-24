import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/people_tags/data/model/people_tags_error_mapper.dart';
import 'package:tentura/features/people_tags/domain/people_tags_exception.dart';

void main() {
  group('people tags name-taken error', () {
    test('uses the server code 1900 (people tags code space + index 0)', () {
      expect(PeopleTagsNameTakenException.codeNumber, 1900);
    });

    test('says "You already have this tag" in English', () {
      expect(
        const PeopleTagsNameTakenException().toEn,
        'You already have this tag',
      );
    });

    test('says "Такой тег уже есть" in Russian', () {
      expect(const PeopleTagsNameTakenException().toRu, 'Такой тег уже есть');
    });

    test('throwIfPeopleTagsError turns the server code into the exception', () {
      expect(
        () => throwIfPeopleTagsError(PeopleTagsNameTakenException.codeNumber),
        throwsA(isA<PeopleTagsNameTakenException>()),
      );
    });

    test('throwIfPeopleTagsError ignores foreign and null codes', () {
      expect(() => throwIfPeopleTagsError(null), returnsNormally);
      expect(() => throwIfPeopleTagsError(1401), returnsNormally);
      expect(() => throwIfPeopleTagsError(1800), returnsNormally);
    });
  });
}
