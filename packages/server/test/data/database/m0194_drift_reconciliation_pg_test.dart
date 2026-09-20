@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// `m0194` reconciles the deployed databases with the schema the chain builds.
/// It is exercised by winding a baseline database back to the shape
/// `ssh.tentura.io` was found in on 2026-09-20 and checking that applying the
/// registry converges it — that state is not otherwise reachable, since it came
/// from migrations being edited after those databases had stamped them.
///
/// The whole fixture runs **once** in [setUpAll] and the tests assert against
/// captured readings. Doing it per test cost five disposable databases and nine
/// schema upgrades, and `migrateDbSchema` takes a *cluster-wide* advisory lock
/// (`tentura_schema_upgrade`): that much extra serialization pushed
/// `capability_evidence_repository_pg_test`'s five-second pair-lock race over
/// its budget every time the full pg suite ran.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0194_DRIFT_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0194',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late _Readings before;
  late _Readings after;
  late String digestAfterForOptedOutAccount;
  late int presenceRowsForAccountCreatedAfter;

  if (reachable) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        lastInclusiveVersion: '0193',
      );
      final writer = session.writer;

      for (final statement in _driftStatements) {
        await writer.execute(statement);
      }
      // An account created while the trigger is the drifted one gets no
      // presence row, the way prod's four accounts did not.
      await writer.execute(
        'INSERT INTO public."user" (id, display_name, public_key) '
        "VALUES ('Udrift01', 'Drifted', 'drift-key-1')",
      );
      // An account that has opted out of the digest, to prove m0194 does not
      // repeat the original m0123 row backfill and re-subscribe it.
      await writer.execute(
        'INSERT INTO public.notification_preference (account_id, email_digest) '
        "VALUES ('Udrift01', 'off')",
      );

      before = await _read(writer);

      await migrateDbSchema(writer);

      after = await _read(writer);
      digestAfterForOptedOutAccount =
          (await writer.execute(
            'SELECT email_digest FROM public.notification_preference '
            "WHERE account_id = 'Udrift01'",
          )).single.single!
              as String;

      await writer.execute(
        'INSERT INTO public."user" (id, display_name, public_key) '
        "VALUES ('Udrift02', 'After fix', 'drift-key-2')",
      );
      presenceRowsForAccountCreatedAfter =
          (await writer.execute(
            'SELECT count(*)::int FROM public.user_presence '
            "WHERE user_id = 'Udrift02'",
          )).single.single!
              as int;
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });
  }

  test(
    'the fixture really is drifted before the migration runs',
    () {
      expect(before.overloads, 2);
      expect(before.triggerSeedsPresence, isFalse);
      expect(before.usersWithoutPresence, 1);
      expect(before.digestDefault, "'off'::text");
      expect(before.categoriesDefault, isNot(contains("'coordination'")));
    },
    skip: skipReason,
  );

  test(
    'drops the pre-m0133 four-argument realtime overload',
    () => expect(after.overloads, 1),
    skip: skipReason,
  );

  test(
    'restores the presence-seeding trigger and backfills the gap',
    () {
      expect(after.triggerSeedsPresence, isTrue);
      expect(after.usersWithoutPresence, 0);
      expect(presenceRowsForAccountCreatedAfter, 1);
    },
    skip: skipReason,
  );

  test(
    'restates the notification_preference defaults the chain lost',
    () {
      expect(after.digestDefault, "'daily'::text");
      expect(after.categoriesDefault, contains("'coordination'"));
    },
    skip: skipReason,
  );

  test(
    'm0195 drops the one-shot cleanup helper a 0193 database still carries',
    () {
      expect(
        before.cleanupHelperPresent,
        isTrue,
        reason: 'a database at 0193 has it — m0193 carries the definition',
      );
      expect(after.cleanupHelperPresent, isFalse);
    },
    skip: skipReason,
  );

  test(
    'leaves an account that opted out of the digest opted out',
    () => expect(digestAfterForOptedOutAccount, 'off'),
    skip: skipReason,
  );
}

/// The shape `ssh.tentura.io` was in: the pre-`m0133` overload alongside the
/// current one, `m0003`'s trigger, and the chain's notification defaults.
const _driftStatements = <String>[
  r'''
CREATE OR REPLACE FUNCTION public.emit_realtime_entity_change(
  p_entity text, p_id text, p_event text, p_user_ids text[]
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_notify('entity_changes', '{}');
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.on_user_created() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO user_vsids
    VALUES (NEW.id, DEFAULT, DEFAULT);
  RETURN NEW;
END;
$$;
''',
  _driftDigestDefault,
  _driftCategoriesDefault,
];

const _driftDigestDefault =
    'ALTER TABLE public.notification_preference '
    "ALTER COLUMN email_digest SET DEFAULT 'off';";

const _driftCategoriesDefault =
    'ALTER TABLE public.notification_preference '
    'ALTER COLUMN email_categories '
    "SET DEFAULT ARRAY['asksOfMe','connections'];";

/// One round of every reading the tests compare, so the fixture only has to be
/// built once.
class _Readings {
  const _Readings({
    required this.overloads,
    required this.triggerSeedsPresence,
    required this.usersWithoutPresence,
    required this.digestDefault,
    required this.categoriesDefault,
    required this.cleanupHelperPresent,
  });

  final int overloads;
  final bool triggerSeedsPresence;
  final int usersWithoutPresence;
  final String digestDefault;
  final String categoriesDefault;
  final bool cleanupHelperPresent;
}

Future<_Readings> _read(Connection writer) async {
  final row = await writer.execute('''
SELECT
  (SELECT count(*)::int FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'emit_realtime_entity_change'),
  (SELECT pg_get_functiondef('public.on_user_created()'::regprocedure)
            LIKE '%user_presence%'),
  (SELECT count(*)::int FROM public."user" u
    WHERE NOT EXISTS (
      SELECT 1 FROM public.user_presence pr WHERE pr.user_id = u.id
    )),
  (SELECT column_default FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'notification_preference'
      AND column_name = 'email_digest'),
  (SELECT column_default FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'notification_preference'
      AND column_name = 'email_categories'),
  (SELECT to_regprocedure(
     'public.nested_requests_apply_legacy_cleanup()') IS NOT NULL)
''');
  final values = row.single;
  return _Readings(
    overloads: values[0]! as int,
    triggerSeedsPresence: values[1]! as bool,
    usersWithoutPresence: values[2]! as int,
    digestDefault: values[3]! as String,
    categoriesDefault: values[4]! as String,
    cleanupHelperPresent: values[5]! as bool,
  );
}
