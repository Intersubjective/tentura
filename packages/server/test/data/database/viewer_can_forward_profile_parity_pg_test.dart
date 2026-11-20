@Tags(['pg', 'repo-files'])
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/viewer_can_forward_profile.dart';

const _expected = {
  'open policy and readable involvement': true,
  'author with closed policy': true,
  'non-author with closed policy': false,
  'author of a Request that needs more help': true,
  'author of a Request with enough help': true,
  'terminal status': false,
  'trusted contact on private Request without involvement access': false,
  'empty session on an open Request': false,
};

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_VIEWER_CAN_FORWARD_PARITY_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_parity',
  );
  final skip = await pgSkipReason(target);
  late final Connection writer;

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(
      target: target,
      lastInclusiveVersion: '0318',
    );
    addTearDown(() => tearDownDisposablePgWriter(session: session));
    writer = session.writer;
  });

  test(
    'the benchmark delivery preserves the forwarding flag and Hasura signature',
    () async {
      await _seed(writer);
      final oracle = await _forwardingFlags(writer);
      final oracleDefinition = await _functionDefinition(writer);
      expect(
        oracle,
        _expected,
        reason: 'the seeded cases must exercise both outcomes',
      );

      await migrateDbSchemaThrough(writer, '0324');
      final beforeDelivery = await _functionDefinition(writer);
      expect(
        beforeDelivery,
        oracleDefinition,
        reason: 'the shipped schema must retain the reference function body',
      );
      final note = File('../../$forwardingProfilePath');
      final markdown = note.existsSync() ? note.readAsStringSync() : '';
      final verdicts = [
        if (markdown.isNotEmpty)
          for (final operation in forwardingProfileOperations.values)
            forwardingProfileVerdict(
              forwardingProfileSection(markdown, operation),
            ),
      ];
      final needsFix = verdicts.contains(true);
      if (needsFix) {
        expect(
          migrationsForTesting
              .map((migration) => migration.version)
              .skipWhile(
                (version) => version != '0324',
              )
              .take(2),
          ['0324', '0325'],
          reason: 'a measured regression needs the next registered migration',
        );
        await migrateDbSchemaThrough(writer, '0325');
      }

      final signature = await writer.execute('''
SELECT proargnames, pg_get_function_result(oid)
FROM pg_proc
WHERE oid = to_regprocedure(
  'public.beacon_get_viewer_can_forward(public.beacon, json)'
)
''');
      expect(signature.map((row) => row.toList()), [
        [
          ['beacon_row', 'hasura_session'],
          'boolean',
        ],
      ]);
      expect(await _forwardingFlags(writer), oracle);
      expect(
        markdown,
        isNotEmpty,
        reason:
            'the benchmark note must establish which schema is being delivered',
      );
      expect(
        await _functionDefinition(writer),
        needsFix ? isNot(beforeDelivery) : beforeDelivery,
        reason:
            'the deployed function body should change only for a measured regression',
      );
      if (needsFix) await _expectExistingUpgradeRegression();
    },
    skip: skip,
  );
}

Future<void> _expectExistingUpgradeRegression() async {
  const regression =
      'upgrading corrects the flag for an existing non-discoverable Request';
  // Run only the existing regression. Its own fixture upgrades from before
  // the forwarding flag change through the current registered migrations.
  // This child already runs inside the outer test-cleanup job.
  final result = await Process.run(
    'timeout',
    [
      '--kill-after=5s',
      '90s',
      Platform.resolvedExecutable,
      'test',
      '--reporter=expanded',
      '--plain-name=$regression',
      'test/domain/use_case/trusted_contact_request_forwarding_pg_test.dart',
    ],
    environment: {'TENTURA_PG_TESTS_REQUIRED': '1'},
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  expect(result.stdout, contains(regression));
  expect(result.stdout, contains('+1: All tests passed!'));
}

Future<Object?> _functionDefinition(Connection writer) async =>
    (await writer.execute('''
SELECT pg_get_functiondef(
  'public.beacon_get_viewer_can_forward(public.beacon, json)'::regprocedure
)
''')).single.single;

Future<Map<String, bool?>> _forwardingFlags(Connection writer) async {
  final rows = await writer.execute('''
WITH cases (scenario, beacon_id, viewer_id, closed_policy) AS (
  VALUES
    ('open policy and readable involvement', 'Bprofileopen', 'Uprofilecontact', false),
    ('author with closed policy', 'Bprofileopen', 'Uprofileauthor', true),
    ('non-author with closed policy', 'Bprofileopen', 'Uprofilecontact', true),
    ('author of a Request that needs more help', 'Bprofileneeds', 'Uprofileauthor', false),
    ('author of a Request with enough help', 'Bprofileenough', 'Uprofileauthor', false),
    ('terminal status', 'Bprofileclosed', 'Uprofileauthor', false),
    ('trusted contact on private Request without involvement access',
      'Bprofileprivate', 'Uprofilecontact', false),
    ('empty session on an open Request', 'Bprofileopen', NULL, false)
)
SELECT scenario, public.beacon_get_viewer_can_forward(
  CASE WHEN closed_policy
       THEN jsonb_populate_record(b, '{"forward_policy": 0}'::jsonb)
       ELSE b END,
  CASE WHEN viewer_id IS NULL THEN '{}'::json
       ELSE json_build_object('x-hasura-role', 'user', 'x-hasura-user-id', viewer_id)
  END
)
FROM cases
JOIN public.beacon b ON b.id = cases.beacon_id
''');
  // A stored Request must have an open policy. A typed row exercises the
  // closed-policy inputs while preserving the real Request's involvement data.
  return {for (final row in rows) row[0]! as String: row[1] as bool?};
}

Future<void> _seed(Connection writer) async {
  for (final (index, id) in ['Uprofileauthor', 'Uprofilecontact'].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key) VALUES (@id, @id, @key)
'''),
      parameters: {
        'id': id,
        'key': pgTestPublicKey('forward-profile', index + 1),
      },
    );
  }
  await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount) VALUES
  ('Uprofileauthor', 'Uprofilecontact', 1),
  ('Uprofilecontact', 'Uprofileauthor', 1)
''');
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   forward_policy, published_at)
VALUES
  ('Bprofileopen', 'Uprofileauthor', 'Open', '', 0, 0, true, 1, now()),
  ('Bprofileprivate', 'Uprofileauthor', 'Private', '', 0, 0, false, 1, now()),
  ('Bprofileneeds', 'Uprofileauthor', 'Needs more help', '', 7, 0, true, 1, now()),
  ('Bprofileenough', 'Uprofileauthor', 'Enough help', '', 8, 0, true, 1, now()),
  ('Bprofileclosed', 'Uprofileauthor', 'Closed', '', 6, 0, true, 1, now())
''');
}
