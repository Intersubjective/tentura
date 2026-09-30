@Tags(['pg'])
library;

import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// MeritRank boundary: the evidence ledger alone does not project an edge;
/// `trust_project_pair` does (m0202).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TRUST_MR_BOUNDARY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_tmb',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late TenturaDb db;

  const aliceId = 'UtmbAlice001';
  const bobId = 'UtmbBob00001';
  const allIds = [aliceId, bobId];

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = openDisposablePgDatabase(target);
      for (var i = 0; i < allIds.length; i++) {
        final id = allIds[i];
        await db.customStatement(
          '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', '${pgTestPublicKey('mbr', i + 1)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        );
      }
    });

    tearDown(() async {
      final idList = allIds.map((id) => "'$id'").join(', ');
      await db.customStatement(
        'DELETE FROM public.trust_evidence '
        'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
      );
      await db.customStatement(
        'DELETE FROM public.user_trust_edge '
        'WHERE subject IN ($idList) OR object IN ($idList)',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: db);
    });
  }

  Future<void> recordEvidence(int kind, double count) => db.customStatement(
    '''
INSERT INTO public.trust_evidence
  (id, subject_user_id, object_user_id, kind, count, source_key)
VALUES ('mbr-ev-$aliceId-$bobId', '$aliceId', '$bobId', $kind, $count,
        'mbr:$aliceId:$bobId')
''',
  );

  test('ledger-only write does not create effective projection row', () async {
    await recordEvidence(2, 1);
    final effective = await db
        .customSelect(
          "SELECT COUNT(*)::int AS c FROM user_trust_edge WHERE subject = '$aliceId'",
        )
        .getSingle();
    expect(effective.read<int>('c'), 0);
  }, skip: skipReason);

  test('projection publishes effective row for the pair', () async {
    await recordEvidence(2, 2);
    await db
        .customSelect(
          r'SELECT public.trust_project_pair($1, $2)',
          variables: [
            Variable<String>(aliceId),
            Variable<String>(bobId),
          ],
        )
        .getSingle();
    final effective = await db
        .customSelect(
          "SELECT COUNT(*)::int AS c FROM user_trust_edge WHERE subject = '$aliceId'",
        )
        .getSingle();
    expect(effective.read<int>('c'), 1);
  }, skip: skipReason);
}
