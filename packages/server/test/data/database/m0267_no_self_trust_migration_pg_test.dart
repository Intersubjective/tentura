@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

// m0267: a self trust edge (left behind by the old own-invite bug) made
// MeritRank refuse the whole bulk load, emptying its graph. The migration
// drops self rows, forbids new ones, and keeps meritrank_init from sending
// any.
const _qa = 'Uselftrust001';
const _other = 'Uselftrust002';

Future<void> main() async {
  test('m0267 is the last registered migration, after 0265', () {
    final versions = migrationsForTesting.map((m) => m.version).toList();
    expect(versions, contains('0267'));
    expect(versions.indexOf('0267'), versions.indexOf('0265') + 1);
  });

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0267_NO_SELF_TRUST_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0267_no_self_trust',
  );
  final pgSkip = await pgSkipReason(target);

  group('upgrade from 0265', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        lastInclusiveVersion: '0265',
      );
    });
    tearDownAll(() async => tearDownDisposablePgWriter(session: session));

    Future<int> count(String sql) async =>
        (await session.writer.execute(sql)).single.single! as int;

    test('drops self rows, forbids new ones, keeps real edges', () async {
      final w = session.writer;
      for (final id in [_qa, _other]) {
        await w.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key, '
            'created_at, updated_at) VALUES (@id, @id, @pk, '
            "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
          ),
          parameters: {'id': id, 'pk': 'pk-$id'},
        );
      }
      // What the own-invite bug left behind, plus one real edge.
      await w.execute(
        'INSERT INTO public.vote_user (subject, object, amount) '
        "VALUES ('$_qa', '$_qa', 1), ('$_qa', '$_other', 1)",
      );
      await w.execute(
        'INSERT INTO public.user_trust_edge '
        '(subject, object, trust_w, target_w) '
        "VALUES ('$_qa', '$_qa', 0.5, 0.5), ('$_qa', '$_other', 0.5, 0.5) "
        'ON CONFLICT (subject, object) DO NOTHING',
      );

      await migrateDbSchemaThrough(w, '0267');

      expect(
        await count(
          'SELECT count(*)::int FROM public.vote_user WHERE subject = object',
        ),
        0,
      );
      expect(
        await count(
          'SELECT count(*)::int FROM public.user_trust_edge '
          'WHERE subject = object',
        ),
        0,
      );
      expect(
        await count(
          'SELECT count(*)::int FROM public.vote_user '
          "WHERE subject = '$_qa' AND object = '$_other'",
        ),
        1,
        reason: 'real trust stays',
      );

      const selfVote =
          'INSERT INTO public.vote_user (subject, object, amount) '
          "VALUES ('$_other', '$_other', 1)";
      const selfEdge =
          'INSERT INTO public.user_trust_edge (subject, object, target_w) '
          "VALUES ('$_other', '$_other', 0.5)";
      for (final insert in [selfVote, selfEdge]) {
        await expectLater(
          w.execute(insert),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23514'),
          ),
          reason: insert,
        );
      }

      final init = await w.execute(
        "SELECT pg_get_functiondef('public.meritrank_init()'::regprocedure)",
      );
      expect(init.single.single! as String, contains('subject <> object'));
    }, skip: pgSkip);
  });
}
