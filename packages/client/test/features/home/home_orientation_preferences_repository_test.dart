import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/database/database.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/home/data/repository/home_orientation_preferences_repository.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Database database;
  late HomeOrientationPreferencesRepository repository;

  setUp(() {
    database = Database(const Env(), Logger('test'), NativeDatabase.memory());
    repository = HomeOrientationPreferencesRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('HomeOrientationPreferencesRepository', () {
    test('setActivated and isActivated round-trip per user id', () async {
      const userId = 'user-a';

      expect(await repository.isActivated(userId: userId), isFalse);

      await repository.setActivated(userId: userId);

      expect(await repository.isActivated(userId: userId), isTrue);
    });

    test(
      'setOrientationDismissed and isOrientationDismissed round-trip per user id',
      () async {
        const userId = 'user-a';

        expect(await repository.isOrientationDismissed(userId: userId), isFalse);

        await repository.setOrientationDismissed(userId: userId);

        expect(await repository.isOrientationDismissed(userId: userId), isTrue);
      },
    );

    test('per-user latches are isolated across user ids', () async {
      const userA = 'user-a';
      const userB = 'user-b';

      await repository.setActivated(userId: userA);
      await repository.setOrientationDismissed(userId: userB);

      expect(await repository.isActivated(userId: userA), isTrue);
      expect(await repository.isActivated(userId: userB), isFalse);
      expect(await repository.isOrientationDismissed(userId: userA), isFalse);
      expect(await repository.isOrientationDismissed(userId: userB), isTrue);
    });

    test(
      'resetFirstRunState clears both per-user latches and leaves override',
      () async {
        const userId = 'user-a';

        await repository.setActivated(userId: userId);
        await repository.setOrientationDismissed(userId: userId);
        await repository.setDebugOverride(OrientationDebugOverride.show);

        await repository.resetFirstRunState(userId: userId);

        expect(await repository.isActivated(userId: userId), isFalse);
        expect(await repository.isOrientationDismissed(userId: userId), isFalse);
        expect(
          await repository.getDebugOverride(),
          OrientationDebugOverride.show,
        );
      },
    );

    test('garbage debug override string reads back as auto', () async {
      await database.managers.settings.create(
        (o) => o(
          key: 'home:orientationDebugOverride',
          valueText: const Value('not-a-valid-override'),
        ),
        mode: InsertMode.insertOrReplace,
      );

      expect(
        await repository.getDebugOverride(),
        OrientationDebugOverride.auto,
      );
    });
  });
}
