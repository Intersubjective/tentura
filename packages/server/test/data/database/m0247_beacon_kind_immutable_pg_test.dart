@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// m0247 (budding E1, Arch §2.4, I5): `beacon.kind` never changes after
/// insert. A Post no longer turns into a Request in place (budding creates a
/// child Request instead); the one-way forward-policy clause of m0209 stays.
const _author = 'Um0246author1';
const _request = 'Bm0246request';
const _post = 'Bm0246post001';
const _draftPost = 'Bm0246draft01';

const _checkViolation = '23514';

final _throwsCheckViolation = throwsA(
  isA<ServerException>().having((e) => e.code, 'code', _checkViolation),
);

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0247_KIND_IMMUTABLE_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0247_kind_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0247_KIND_IMMUTABLE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0247_kind',
  );
  final pgSkip =
      await pgSkipReason(migrationTarget) ?? await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: '0246',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('a Post written before the migration can no longer become a '
        'Request', () async {
      final writer = session.writer;
      await _seed(writer);

      await migrateDbSchema(writer);

      await expectLater(_convert(writer, _post), _throwsCheckViolation);
      expect(await _kind(writer, _post), 1);
    });
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
    });

    setUp(() async => _seed(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('an open Post cannot become a Request', () async {
      await expectLater(_convert(writer, _post), _throwsCheckViolation);
      expect(await _kind(writer, _post), 1);
    });

    test('a draft Post cannot become a Request', () async {
      await expectLater(
        writer.execute(
          "UPDATE public.beacon SET kind = 0 WHERE id = '$_draftPost'",
        ),
        _throwsCheckViolation,
      );
      expect(await _kind(writer, _draftPost), 1);
    });

    test('a Request cannot become a Post', () async {
      await expectLater(
        writer.execute(
          "UPDATE public.beacon SET kind = 1 WHERE id = '$_request'",
        ),
        _throwsCheckViolation,
      );
      expect(await _kind(writer, _request), 0);
    });

    test('writing the same kind back is not a change', () async {
      await writer.execute(
        "UPDATE public.beacon SET kind = kind WHERE id IN ('$_request', '$_post')",
      );
      expect(await _kind(writer, _request), 0);
      expect(await _kind(writer, _post), 1);
    });

    test('a published Post still cannot close its forward policy', () async {
      await expectLater(
        writer.execute(
          "UPDATE public.beacon SET forward_policy = 0 WHERE id = '$_post'",
        ),
        _throwsCheckViolation,
      );
      expect(await _forwardPolicy(writer, _post), 1);
    });

    test('a draft Post may still close its forward policy', () async {
      await writer.execute(
        "UPDATE public.beacon SET forward_policy = 0 WHERE id = '$_draftPost'",
      );
      expect(await _forwardPolicy(writer, _draftPost), 0);
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute(
    'TRUNCATE TABLE public.beacon, public."user" CASCADE',
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
    parameters: {'id': _author, 'key': pgTestPublicKey('m0247', 1)},
  );
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', 'desc', 0, now())
''');
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   forward_policy, published_at)
VALUES
  ('$_post', '$_author', '', '', 0, 1, false, 1, now()),
  ('$_draftPost', '$_author', '', '', 3, 1, false, 1, NULL)
''');
}

/// The statement the removed `convertPostToRequest` used to run.
Future<void> _convert(Connection writer, String id) => writer.execute('''
UPDATE public.beacon
SET title = 'Converted', description = 'd', kind = 0, forward_policy = 1,
    is_discoverable = true, updated_at = now()
WHERE id = '$id' AND kind = 1 AND status = 0
''');

Future<int> _kind(Connection writer, String id) async =>
    (await writer.execute(
          "SELECT kind FROM public.beacon WHERE id = '$id'",
        )).single.single!
        as int;

Future<int> _forwardPolicy(Connection writer, String id) async =>
    (await writer.execute(
          "SELECT forward_policy FROM public.beacon WHERE id = '$id'",
        )).single.single!
        as int;
