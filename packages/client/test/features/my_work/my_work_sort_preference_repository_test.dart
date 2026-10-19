import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/database/database.dart' hide isNotNull, isNull;
import 'package:tentura/env.dart';
import 'package:tentura/features/my_work/data/repository/my_work_sort_preference_repository.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_sort.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Database database;
  late MyWorkSortPreferenceRepository repository;

  setUp(() {
    database = Database(const Env(), Logger('test'), NativeDatabase.memory());
    repository = MyWorkSortPreferenceRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('MyWorkSortPreferenceRepository (#431)', () {
    test('nothing saved reads as null', () async {
      expect(await repository.getSort(), isNull);
    });

    test('every order round-trips and the last write wins', () async {
      for (final sort in MyWorkSort.values) {
        await repository.setSort(sort);
        expect(await repository.getSort(), sort);
      }
      await repository.setSort(MyWorkSort.oldest);
      expect(await repository.getSort(), MyWorkSort.oldest);
    });

    test('a value from a different repository instance on the same database '
        'is read back (the reload case)', () async {
      await repository.setSort(MyWorkSort.alphabetical);
      final reopened = MyWorkSortPreferenceRepository(database);
      expect(await reopened.getSort(), MyWorkSort.alphabetical);
    });

    for (final bad in ['bogus', '']) {
      test(
        'a stored value that is not a known order ("$bad") reads as null',
        () async {
          // Let the repository write its own row, then corrupt it in place
          // (an old/renamed enum value or an empty string), without pinning
          // the key name.
          await repository.setSort(MyWorkSort.oldest);
          final changed =
              await (database.update(database.settings)
                    ..where((t) => t.valueText.equals(MyWorkSort.oldest.name)))
                  .write(SettingsCompanion(valueText: Value(bad)));
          expect(changed, 1, reason: 'the sort is stored as valueText = name');

          expect(await repository.getSort(), isNull);
          expect(
            await MyWorkSortPreferenceRepository(database).getSort(),
            isNull,
          );
        },
      );
    }
  });
}
