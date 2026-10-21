@Tags(['pg'])
library;

// #489 (round 7) pg twin of test/api/closure_member_names_test.dart:
// `ClosureRepository.members` returns each member's `user.display_name` and
// `user.image_id` with the row, the removed member included, so the closure
// screens never fall back to the raw user id.

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';

import '../support/disposable_pg_target.dart';
import '../support/pg_test_public_keys.dart';

const _authorId = 'Uclnmpgauth01';
const _helperId = 'Uclnmpghelp01';
const _removedId = 'Uclnmpgremv01';
const _beaconId = 'Bclnmpgbeac01';
const _imageId = '6f1d2a7e-4b8c-4d1e-9f00-00000000a489';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CLOSURE_MEMBER_NAMES_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_closure_member_names',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late ClosureRepositoryPort repo;

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      repo = ClosureRepository(database);
      await _seed(writer);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  test(
    'members carry display name and avatar id, a removed member too',
    () async {
      await repo.createEpoch(
        beaconId: _beaconId,
        epoch: 1,
        openedAt: DateTime.utc(2026, 10),
        closesAt: DateTime.utc(2026, 10, 8),
      );
      await repo.insertMembers(
        beaconId: _beaconId,
        epoch: 1,
        members: const [
          ClosureMemberInsert(userId: _helperId, activeAtOpen: true),
          ClosureMemberInsert(userId: _removedId, activeAtOpen: true),
        ],
      );
      await repo.setDeparture(
        beaconId: _beaconId,
        epoch: 1,
        userId: _removedId,
        departure: Departure.removed,
      );

      final rows = {
        for (final r in await repo.members(beaconId: _beaconId, epoch: 1))
          r.userId: r,
      };

      expect(rows.keys.toSet(), {_helperId, _removedId});
      expect(rows[_removedId]!.departure, Departure.removed);
      expect(rows[_removedId]!.displayName, 'Rita Removed');
      expect(rows[_removedId]!.avatarId, _imageId);
      expect(rows[_helperId]!.displayName, 'Hana Helper');
      expect(rows[_helperId]!.avatarId, isNull);
    },
    skip: skipReason,
  );
}

Future<void> _seed(Connection writer) async {
  Future<void> user(String id, String name, int slot) async {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$name', '${pgTestPublicKey('clnmpg', slot)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
  }

  await user(_authorId, 'Ada Author', 1);
  await user(_helperId, 'Hana Helper', 2);
  await user(_removedId, 'Rita Removed', 3);
  await writer.execute('''
INSERT INTO public.image (id, author_id, height, width, hash)
VALUES ('$_imageId'::uuid, '$_removedId', 48, 64, 'blur489')
''');
  await writer.execute('''
UPDATE public."user" SET image_id = '$_imageId'::uuid WHERE id = '$_removedId'
''');
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES (
  '$_beaconId', '$_authorId', 'closure member names', '',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
''');
}
