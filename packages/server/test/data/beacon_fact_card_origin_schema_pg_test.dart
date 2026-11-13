@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_outcome.dart';

import '../support/disposable_pg_target.dart';
import '../support/pg_test_public_keys.dart';

const _user = 'Uorigin00001';
const _beaconA = 'Borigin00001';
const _beaconB = 'Borigin00002';
const _originCk = 'beacon_fact_card_origin_ck';
const _liveCopyIdx = 'beacon_fact_card_one_live_copy_idx';
const _sourceFact = 'Forigsrc0001';

/// Database-level contract of a fact copied from another fact: the three
/// origin columns are all-or-nothing, a beacon holds one live copy per origin,
/// origin is write-once, and the revision kind accepts "copied" (4).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_ORIGIN_SCHEMA_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_origin_schema',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('beacon_fact_card origin columns', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    var n = 0;

    String nextId() => 'Forig${(++n).toString().padLeft(7, '0')}';

    Future<void> insertFact({
      required String id,
      String beacon = _beaconA,
      int status = 0,
      String? originId,
      int? originSeq,
      int? originKind,
    }) {
      final hasOrigin =
          originId != null || originSeq != null || originKind != null;
      return writer.execute(
        Sql.named(
          hasOrigin
              ? '''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status,
   origin_fact_card_id, origin_revision_seq, origin_beacon_kind)
VALUES (@id, @beacon, 'text', 0, @user, @status, @oid, @oseq, @okind)
'''
              : '''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status)
VALUES (@id, @beacon, 'text', 0, @user, @status)
''',
        ),
        parameters: {
          'id': id,
          'beacon': beacon,
          'user': _user,
          'status': status,
          if (hasOrigin) ...{
            'oid': originId,
            'oseq': originSeq,
            'okind': originKind,
          },
        },
      );
    }

    Future<void> insertRevision(String factId, int seq, int kind) =>
        writer.execute(
          Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind)
VALUES (@id, @seq, 'text', @user, @kind)
'''),
          parameters: {'id': factId, 'seq': seq, 'user': _user, 'kind': kind},
        );

    Future<Object?> column(String id, String col) async {
      final r = await writer.execute(
        Sql.named('SELECT $col FROM public.beacon_fact_card WHERE id = @id'),
        parameters: {'id': id},
      );
      return r.single.single;
    }

    Matcher violates(String sqlState, String constraint) => throwsA(
      isA<ServerException>()
          .having((e) => e.code, 'code', sqlState)
          .having((e) => e.constraintName, 'constraintName', constraint),
    );

    // The write-once guard: raised by the trigger itself (not a missing
    // column or other SQL error) and says which column family it protects.
    final originGuard = throwsA(
      isA<ServerException>()
          .having((e) => e.code, 'code', isNot(startsWith('42')))
          .having(
            (e) => e.message.toLowerCase(),
            'message',
            contains('origin'),
          ),
    );

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {'id': _user, 'key': pgTestPublicKey('factorig', 1)},
        );
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES (@a, @u, 't', 'd', 0, now(), false),
       (@b, @u, 't2', 'd2', 0, now(), false)
'''),
          parameters: {'a': _beaconA, 'b': _beaconB, 'u': _user},
        );
        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ),
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    test(
      'a row with only origin_fact_card_id set is rejected by the origin check',
      () async {
        await expectLater(
          insertFact(id: nextId(), originId: _sourceFact),
          violates('23514', _originCk),
        );
      },
      skip: skipReason,
    );

    test(
      'a full origin triple missing only origin_revision_seq is rejected',
      () async {
        await expectLater(
          insertFact(id: nextId(), originId: _sourceFact, originKind: 0),
          violates('23514', _originCk),
        );
      },
      skip: skipReason,
    );

    test(
      'a full origin triple missing only origin_beacon_kind is rejected',
      () async {
        await expectLater(
          insertFact(id: nextId(), originId: _sourceFact, originSeq: 1),
          violates('23514', _originCk),
        );
      },
      skip: skipReason,
    );

    test(
      'a full origin triple is accepted and read back unchanged',
      () async {
        final id = nextId();
        await insertFact(
          id: id,
          beacon: _beaconB,
          originId: 'Forigfull001',
          originSeq: 3,
          originKind: 1,
        );
        expect(await column(id, 'origin_fact_card_id'), 'Forigfull001');
        expect(await column(id, 'origin_revision_seq'), 3);
        expect(await column(id, 'origin_beacon_kind'), 1);
      },
      skip: skipReason,
    );

    test(
      'origin_beacon_kind 2 is rejected',
      () async {
        await expectLater(
          insertFact(
            id: nextId(),
            originId: _sourceFact,
            originSeq: 1,
            originKind: 2,
          ),
          violates('23514', _originCk),
        );
      },
      skip: skipReason,
    );

    test(
      'origin_revision_seq 0 is rejected, seq 1 with kind 1 is accepted',
      () async {
        await expectLater(
          insertFact(
            id: nextId(),
            originId: 'Forigseq0001',
            originSeq: 0,
            originKind: 0,
          ),
          violates('23514', _originCk),
        );
        final id = nextId();
        await insertFact(
          id: id,
          originId: 'Forigseq0002',
          originSeq: 1,
          originKind: 1,
        );
        expect(await column(id, 'origin_revision_seq'), 1);
      },
      skip: skipReason,
    );

    test(
      'ordinary facts without origin never collide on the one-live-copy index',
      () async {
        await insertFact(id: nextId());
        await insertFact(id: nextId());
        final id = nextId();
        await insertFact(id: id);
        expect(await column(id, 'origin_fact_card_id'), isNull);
        expect(await column(id, 'origin_revision_seq'), isNull);
        expect(await column(id, 'origin_beacon_kind'), isNull);
      },
      skip: skipReason,
    );

    test(
      'two live copies of one origin in one beacon violate the index',
      () async {
        await insertFact(
          id: nextId(),
          originId: 'Forigdup0001',
          originSeq: 1,
          originKind: 0,
        );
        await expectLater(
          insertFact(
            id: nextId(),
            originId: 'Forigdup0001',
            originSeq: 2,
            originKind: 0,
          ),
          violates('23505', _liveCopyIdx),
        );
      },
      skip: skipReason,
    );

    test(
      'a corrected live copy and an active live copy of one origin collide',
      () async {
        await insertFact(
          id: nextId(),
          status: 1,
          originId: 'Forigcor0001',
          originSeq: 1,
          originKind: 0,
        );
        await expectLater(
          insertFact(
            id: nextId(),
            originId: 'Forigcor0001',
            originSeq: 1,
            originKind: 0,
          ),
          violates('23505', _liveCopyIdx),
        );
      },
      skip: skipReason,
    );

    test(
      'a removed copy plus a live copy of one origin do not collide',
      () async {
        await insertFact(
          id: nextId(),
          status: 2,
          originId: 'Forigrem0001',
          originSeq: 1,
          originKind: 0,
        );
        await insertFact(
          id: nextId(),
          originId: 'Forigrem0001',
          originSeq: 1,
          originKind: 0,
        );
      },
      skip: skipReason,
    );

    test(
      'the same origin in different beacons, and different origins in one '
      'beacon, are all accepted',
      () async {
        await insertFact(
          id: nextId(),
          originId: 'Forigmix0001',
          originSeq: 1,
          originKind: 0,
        );
        await insertFact(
          id: nextId(),
          beacon: _beaconB,
          originId: 'Forigmix0001',
          originSeq: 1,
          originKind: 0,
        );
        await insertFact(
          id: nextId(),
          originId: 'Forigmix0002',
          originSeq: 1,
          originKind: 0,
        );
      },
      skip: skipReason,
    );

    test(
      'origin survives deletion of its source fact (no foreign key)',
      () async {
        await insertFact(id: _sourceFact, beacon: _beaconB);
        final copy = nextId();
        await insertFact(
          id: copy,
          originId: _sourceFact,
          originSeq: 1,
          originKind: 0,
        );
        await writer.execute(
          Sql.named('DELETE FROM public.beacon_fact_card WHERE id = @id'),
          parameters: {'id': _sourceFact},
        );
        expect(await column(copy, 'origin_fact_card_id'), _sourceFact);
      },
      skip: skipReason,
    );

    for (final c in [
      ('origin_fact_card_id', "'Fsomethingelse'"),
      ('origin_revision_seq', '9'),
      ('origin_beacon_kind', '0'),
    ]) {
      test(
        'updating ${c.$1} alone on a row with origin raises and keeps the '
        'stored value',
        () async {
          final id = nextId();
          await insertFact(
            id: id,
            originId: 'Forigwo${nextId()}',
            originSeq: 2,
            originKind: 1,
          );
          final before = await column(id, c.$1);
          await expectLater(
            writer.execute(
              Sql.named(
                'UPDATE public.beacon_fact_card SET ${c.$1} = ${c.$2} '
                'WHERE id = @id',
              ),
              parameters: {'id': id},
            ),
            originGuard,
          );
          expect(await column(id, c.$1), before);
        },
        skip: skipReason,
      );
    }

    for (final col in [
      'origin_fact_card_id',
      'origin_revision_seq',
      'origin_beacon_kind',
    ]) {
      test(
        'clearing $col to NULL on a row with origin raises and keeps the '
        'stored value',
        () async {
          final id = nextId();
          await insertFact(
            id: id,
            originId: 'Forignul${nextId()}',
            originSeq: 2,
            originKind: 1,
          );
          final before = await column(id, col);
          await expectLater(
            writer.execute(
              Sql.named(
                'UPDATE public.beacon_fact_card SET $col = NULL '
                'WHERE id = @id',
              ),
              parameters: {'id': id},
            ),
            anyOf(originGuard, violates('23514', _originCk)),
          );
          expect(await column(id, col), before);
        },
        skip: skipReason,
      );
    }

    test(
      'setting origin on a row that had none raises',
      () async {
        final id = nextId();
        await insertFact(id: id);
        await expectLater(
          writer.execute(
            Sql.named('''
UPDATE public.beacon_fact_card
SET origin_fact_card_id = 'Foriglate001', origin_revision_seq = 1,
    origin_beacon_kind = 0
WHERE id = @id
'''),
            parameters: {'id': id},
          ),
          originGuard,
        );
        expect(await column(id, 'origin_fact_card_id'), isNull);
      },
      skip: skipReason,
    );

    test(
      'writing an origin column back to its current value together with a '
      'text change succeeds',
      () async {
        final id = nextId();
        await insertFact(
          id: id,
          originId: 'Forigsame001',
          originSeq: 1,
          originKind: 0,
        );
        await writer.execute(
          Sql.named('''
UPDATE public.beacon_fact_card
SET origin_fact_card_id = 'Forigsame001', fact_text = 'changed'
WHERE id = @id
'''),
          parameters: {'id': id},
        );
        expect(await column(id, 'fact_text'), 'changed');
      },
      skip: skipReason,
    );

    test(
      'edit, setVisibility and remove still succeed on a fact with an origin',
      () async {
        final id = nextId();
        await insertFact(
          id: id,
          originId: 'Forigrepo001',
          originSeq: 1,
          originKind: 0,
        );
        await insertRevision(id, 1, BeaconFactCardRevisionKindBits.created);
        final repo = BeaconFactCardRepository(db, BeaconRoomRepository(db));

        final edit = await repo.editText(
          factCardId: id,
          beaconId: _beaconA,
          actorUserId: _user,
          newText: 'edited copy',
          baseRevisionSeq: 1,
          rateWindow: const Duration(hours: 1),
          rateMax: 1000,
          quietWindow: kFactEditQuietWindow,
        );
        expect(edit, isA<FactEditApplied>());
        expect(await column(id, 'fact_text'), 'edited copy');

        await repo.setVisibility(
          factCardId: id,
          beaconId: _beaconA,
          actorUserId: _user,
          visibility: BeaconFactCardVisibilityBits.room,
        );
        expect(
          await column(id, 'visibility'),
          BeaconFactCardVisibilityBits.room,
        );

        expect(
          await repo.remove(
            factCardId: id,
            beaconId: _beaconA,
            actorUserId: _user,
          ),
          isTrue,
        );
        expect(await column(id, 'status'), BeaconFactCardStatusBits.removed);
        expect(await column(id, 'origin_fact_card_id'), 'Forigrepo001');
      },
      skip: skipReason,
    );

    test(
      'revision kinds 0-4 insert and kinds 5 and -1 are rejected',
      () async {
        final id = nextId();
        await insertFact(id: id);
        for (var kind = 0; kind <= 4; kind++) {
          await insertRevision(id, kind + 1, kind);
        }
        await expectLater(
          insertRevision(id, 10, 5),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23514'),
          ),
        );
        await expectLater(
          insertRevision(id, 11, -1),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23514'),
          ),
        );
      },
      skip: skipReason,
    );
  });
}
