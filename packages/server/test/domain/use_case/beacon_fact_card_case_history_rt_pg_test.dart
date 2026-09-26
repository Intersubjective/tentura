@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/query_counter.dart';

/// Lifecycle comes from the fused `loadRoomAccess`; no second status read.
class _UnusedHierarchy extends Fake implements BeaconHierarchyRepositoryPort {}

/// tentura-617.14 (issue #181 plan §8.4, §8.11, §14.7 "RT counting"): one
/// history page through [BeaconFactCardCase] is read-only and costs exactly
/// 2 statements — the fused `loadRoomAccess` SELECT and the repository's
/// keyset `history` SELECT. No BEGIN/COMMIT, no `listForBeacon`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_HISTORY_CASE_RT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_history_case_rt',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconFactCardCase.history RT — disposable Postgres', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late QueryCounter counter;
    late BeaconFactCardCase case_;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        await _seed(writer);

        counter = QueryCounter();
        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ).interceptWith(counter),
        );
        final room = BeaconRoomRepository(db);
        case_ = BeaconFactCardCase(
          BeaconFactCardRepository(db, room),
          room,
          _UnusedHierarchy(),
          FakeBeaconAccessGuard(),
          env: Env(environment: Environment.test),
          logger: Logger('BeaconFactCardCaseHistoryRtPgTest'),
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    test(
      'one history page through the use case costs exactly 2 statements',
      () async {
        counter.reset();
        final page = await case_.history(
          factCardId: _factId,
          beaconId: _beaconId,
          userId: _authorId,
        );
        expect(page.entries, isNotEmpty);
        expect(
          counter.count,
          2,
          reason: 'loadRoomAccess SELECT + history SELECT',
        );
      },
      skip: skipReason,
    );
  });
}

const _authorId = 'Ufchrtauthor';
const _beaconId = 'Bfchrtbeacon';
const _factId = 'Ffchrtfact01';

final _t0 = DateTime.utc(2026, 3, 1, 12);

Future<void> _seed(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
    parameters: {
      'id': _authorId,
      'key': pgTestPublicKey('facthistcasert', 1),
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES (@beacon, @author, 't', 'd', 0, @t0, false)
'''),
    parameters: {'beacon': _beaconId, 'author': _authorId, 't0': _t0},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @beacon, 'Original', ${BeaconFactCardVisibilityBits.public},
        @author, ${BeaconFactCardStatusBits.active}, @at, @at, 1)
'''),
    parameters: {
      'id': _factId,
      'beacon': _beaconId,
      'author': _authorId,
      'at': _t0,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at)
VALUES (@id, 1, 'Original', @author,
        ${BeaconFactCardRevisionKindBits.created}, @at)
'''),
    parameters: {'id': _factId, 'author': _authorId, 'at': _t0},
  );
}
