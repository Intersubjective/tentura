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
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/query_counter.dart';

/// Lifecycle comes from the fused `loadRoomAccess`; no second status read.
class _UnusedImage extends Fake implements ImageRepositoryPort {}

class _UnusedTasks extends Fake implements TaskRepositoryPort {}

class _UnusedHierarchy extends Fake implements BeaconHierarchyRepositoryPort {}

/// tentura-617.11 (issue #181 plan §14.5, §14.7 "RT counting"): one edit
/// through [BeaconFactCardCase] costs exactly 5 statements — the fused
/// `loadRoomAccess` SELECT, then the repository's BEGIN, `set_config` actor
/// line, the edit CTE and COMMIT. No `listForBeacon` to infer the base seq,
/// no separate author / steward / participant / status lookups.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_EDIT_CASE_RT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_edit_case_rt',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconFactCardCase.correct / restore RT — disposable Postgres', () {
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
          _UnusedImage(),
          _UnusedTasks(),
          _UnusedHierarchy(),
          FakeBeaconAccessGuard(),
          env: Env(environment: Environment.test),
          logger: Logger('BeaconFactCardCaseEditRtPgTest'),
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    test(
      'one edit through the use case costs exactly 5 statements',
      () async {
        await _seedFact(writer, id: _factEditId);
        counter.reset();
        final seq = await case_.correct(
          factCardId: _factEditId,
          beaconId: _beaconId,
          actorUserId: _editorId,
          newText: 'Edited through the case',
          baseRevisionSeq: 1,
        );
        expect(seq, 2);
        expect(
          counter.count,
          5,
          reason: 'loadRoomAccess + BEGIN + set_config + edit CTE + COMMIT',
        );
      },
      skip: skipReason,
    );

    test(
      'one restore through the use case costs exactly 5 statements',
      () async {
        await _seedFact(writer, id: _factRestoreId, headSeq: 2);
        counter.reset();
        final seq = await case_.restore(
          factCardId: _factRestoreId,
          beaconId: _beaconId,
          actorUserId: _editorId,
          fromSeq: 1,
          baseRevisionSeq: 2,
        );
        expect(seq, 3);
        expect(
          counter.count,
          5,
          reason: 'loadRoomAccess + BEGIN + set_config + edit CTE + COMMIT',
        );
      },
      skip: skipReason,
    );
  });
}

const _authorId = 'Ufcrtauthor';
const _editorId = 'Ufcrteditor';
const _beaconId = 'Bfcrtbeacon';
const _factEditId = 'Ffcrtedit01';
const _factRestoreId = 'Ffcrtrestr1';

final _t0 = DateTime.utc(2026, 3, 1, 12);

Future<void> _seed(Connection writer) async {
  var n = 0;
  for (final id in [_authorId, _editorId]) {
    n++;
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('factcasert', n)},
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES (@beacon, @author, 't', 'd', 0, @t0, false)
'''),
    parameters: {'beacon': _beaconId, 'author': _authorId, 't0': _t0},
  );
  // The editor is a steward, so room use comes from the fused preflight
  // rather than the author short-circuit.
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES (@beacon, @editor)
'''),
    parameters: {'beacon': _beaconId, 'editor': _editorId},
  );
}

/// Seeds a live fact whose head is revision [headSeq]; revision 1 holds
/// 'Original', later revisions 'Original vN'.
Future<void> _seedFact(
  Connection writer, {
  required String id,
  int headSeq = 1,
}) async {
  final headText = headSeq == 1 ? 'Original' : 'Original v$headSeq';
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @beacon, @text, ${BeaconFactCardVisibilityBits.public},
        @author, ${BeaconFactCardStatusBits.active}, @at, @at, @head)
'''),
    parameters: {
      'id': id,
      'beacon': _beaconId,
      'text': headText,
      'author': _authorId,
      'at': _t0,
      'head': headSeq,
    },
  );
  for (var seq = 1; seq <= headSeq; seq++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at)
VALUES (@id, @seq, @text, @author, @kind, @at)
'''),
      parameters: {
        'id': id,
        'seq': seq,
        'text': seq == 1 ? 'Original' : 'Original v$seq',
        'author': _authorId,
        'kind': seq == 1
            ? BeaconFactCardRevisionKindBits.created
            : BeaconFactCardRevisionKindBits.edited,
        'at': _t0,
      },
    );
  }
}
