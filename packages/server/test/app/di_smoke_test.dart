import 'package:test/test.dart';
import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_coordination_item_case.dart';

import '../support/smoke_env.dart';

void main() {
  for (final entry in [
    ('prod', smokeProdEnv()),
    ('dev', smokeDevEnv()),
  ]) {
    test('DI graph resolves under ${entry.$1}', () async {
      addTearDown(() async => getIt.reset());

      await configureDependencies(entry.$2);

      // Eager singleton — failed on c3ed42c7 dual-@LazySingleton bug.
      expect(getIt.get<UpdateCoordinationItemCase>(), isNotNull);

      // Registration-only path: no live Postgres (CI). TaskWorker and
      // PgNotificationService connect on factory create — skip those unless PG
      // is reachable.
      await getIt.allReady(ignorePendingAsyncCreation: true);

      expect(getIt.isRegistered<BeaconRoomCase>(), isTrue);
      expect(getIt.isRegistered<RootRouter>(), isTrue);
      expect(getIt.isRegistered<BeaconRoomRepositoryPort>(), isTrue);
      expect(getIt.isRegistered<BeaconAccessGuard>(), isTrue);

      if (await smokePostgresReachable(entry.$2)) {
        await getIt.allReady();
        expect(await getIt.getAsync<BeaconRoomCase>(), isNotNull);
        expect(await getIt.getAsync<RootRouter>(), isNotNull);
      }
    });
  }
}
