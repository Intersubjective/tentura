@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// m0212: `beacon_help_offer_request_only` rejects a help offer on a Post at
/// the database level (defence in depth behind the use-case guard and the
/// Hasura insert check).
/// See `docs/plans/post-and-constellation-composer-plan.md` §4.
const _author = 'Um0212author01';
const _helper = 'Um0212helper001';

const _request = 'Bm0212request01';
const _post = 'Bm0212post00001';

const _checkViolation = '23514';

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0212_HELP_OFFER_GUARD_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0212_guard_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0212_HELP_OFFER_GUARD_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0212_guard',
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
        lastInclusiveVersion: '0211',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test(
      'help offers stored before the migration are kept, new ones on a Post '
      'are rejected',
      () async {
        final writer = session.writer;
        await _seedFixture(writer);
        // Pre-migration there is no guard: a legacy offer on a Post can exist.
        await _insertHelpOffer(writer, _post);

        await migrateDbSchema(writer);

        final kept = await writer.execute('''
SELECT count(*) FROM public.beacon_help_offer WHERE beacon_id = '$_post'
''');
        expect(kept.single[0], 1);
        await writer.execute(
          "DELETE FROM public.beacon_help_offer WHERE beacon_id = '$_post'",
        );

        await expectLater(
          _insertHelpOffer(writer, _post),
          _throwsCheckViolation,
        );
        await _insertHelpOffer(writer, _request);
      },
    );
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      await _seedFixture(writer);
    });

    tearDown(() async {
      await writer.execute(
        "DELETE FROM public.beacon_help_offer WHERE beacon_id LIKE 'Bm0212%'",
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('the guard function is installed as a BEFORE INSERT row trigger on '
        'beacon_help_offer', () async {
      final rows = await writer.execute('''
SELECT t.tgtype
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE t.tgrelid = 'public.beacon_help_offer'::regclass
  AND NOT t.tgisinternal
  AND p.proname = 'beacon_help_offer_request_only'
''');
      expect(rows, hasLength(1));
      final tgtype = rows.single[0]! as int;
      expect(tgtype & 1, 1, reason: 'FOR EACH ROW');
      expect(tgtype & 2, 2, reason: 'BEFORE');
      expect(tgtype & 4, 4, reason: 'INSERT');
    });

    test('a help offer on a Request is accepted', () async {
      await _insertHelpOffer(writer, _request);

      final rows = await writer.execute('''
SELECT count(*) FROM public.beacon_help_offer
WHERE beacon_id = '$_request' AND user_id = '$_helper'
''');
      expect(rows.single[0], 1);
    });

    test('a help offer on a Post is rejected with a check violation', () async {
      await expectLater(
        _insertHelpOffer(writer, _post),
        _throwsCheckViolation,
      );

      final rows = await writer.execute('''
SELECT count(*) FROM public.beacon_help_offer WHERE beacon_id = '$_post'
''');
      expect(rows.single[0], 0);
    });

    test('an offer rejected on a Post does not block other offers', () async {
      await expectLater(
        _insertHelpOffer(writer, _post),
        _throwsCheckViolation,
      );
      await _insertHelpOffer(writer, _request);
    });

    test(
      'updating an existing help offer on a Request is not guarded',
      () async {
        await _insertHelpOffer(writer, _request);

        await writer.execute('''
UPDATE public.beacon_help_offer SET message = 'updated'
WHERE beacon_id = '$_request' AND user_id = '$_helper'
''');

        final rows = await writer.execute('''
SELECT message FROM public.beacon_help_offer
WHERE beacon_id = '$_request' AND user_id = '$_helper'
''');
        expect(rows.single[0], 'updated');
      },
    );
  });
}

final _throwsCheckViolation = throwsA(
  isA<ServerException>().having((e) => e.code, 'sqlstate', _checkViolation),
);

Future<void> _seedFixture(Connection writer) async {
  for (final id in [_author, _helper]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
}

Future<void> _insertHelpOffer(Connection writer, String beaconId) =>
    writer.execute('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message)
VALUES ('$beaconId', '$_helper', 'I can help')
''');
