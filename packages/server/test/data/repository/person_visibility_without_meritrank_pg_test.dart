@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/person_visibility_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _viewer = 'Uvnomr000001';
const _stranger = 'Uvnomr000002';
const _friend = 'Uvnomr000003';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERSON_VISIBILITY_NO_MR_TEST_DB',
    defaultNamePrefix: 'tentura_test_person_visibility_no_mr',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('PersonVisibilityRepository on a database without MeritRank', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late Connection writer;
    late PersonVisibilityRepository repository;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      // Plain pg-tagged databases do not ship the MeritRank extension.
      await writer.execute('DROP EXTENSION IF EXISTS pgmer2 CASCADE');
      await writer.execute(
        'DROP FUNCTION IF EXISTS public.mr_mutual_scores(text, text)',
      );
      database = openDisposablePgDatabase(target);
      repository = PersonVisibilityRepository(database);
    });
    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      for (final (i, id) in [_viewer, _stranger, _friend].indexed) {
        await writer.execute(
          Sql.named('''
            INSERT INTO public."user" (id, display_name, public_key)
            VALUES (@id, @id, @key)
          '''),
          parameters: {'id': id, 'key': pgTestPublicKey('vnm', i + 1)},
        );
      }
      await writer.execute(
        Sql.named('''
          INSERT INTO public.vote_user (subject, object, amount)
          VALUES (@a, @b, 1), (@b, @a, 1)
        '''),
        parameters: {'a': _viewer, 'b': _friend},
      );
    });
    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test(
      'the MeritRank function is absent from public in this database',
      () async {
        final rows = await writer.execute(
          'SELECT count(*) FROM pg_proc p '
          'JOIN pg_namespace n ON n.oid = p.pronamespace '
          "WHERE n.nspname = 'public' AND p.proname = 'mr_mutual_scores' "
          "AND pg_get_function_identity_arguments(p.oid) = 'text, text'",
        );
        expect(rows.first.first, 0);
      },
    );

    test(
      'a peer without any trust edge is not visible instead of throwing',
      () async {
        final visible = await repository.personVisiblePeerIds(
          viewerId: _viewer,
          peerIds: const [_stranger],
          context: '',
        );

        expect(visible, isEmpty);
      },
    );

    test('a reciprocally trusted peer stays visible', () async {
      final visible = await repository.personVisiblePeerIds(
        viewerId: _viewer,
        peerIds: const [_friend, _stranger],
        context: '',
      );

      expect(visible, {_friend});
    });
  });
}
