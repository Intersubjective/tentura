@Tags(['pg'])
library;

import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/domain/trust/ledger_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_kind.dart';

import '../../support/disposable_pg_target.dart';

/// `record` dedupes on `source_key` only; other constraint violations raise.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TRUST_LEDGER_CONFLICT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_tlc',
  );
  final postgresReachable = await canReachPostgresAdmin(target);
  final skipReason = postgresReachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  const aliceId = 'Utlcalice0001';
  const bobId = 'Utlcbob000001';
  const sourceKey = 'trust_ledger_conflict:alice:bob';
  const ids = "'$aliceId', '$bobId'";

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late TrustLedgerRepository repo;

  Future<void> cleanup() async {
    await db.customStatement(
      'DELETE FROM public.trust_evidence '
      'WHERE subject_user_id IN ($ids) OR object_user_id IN ($ids)',
    );
    await db.customStatement('DELETE FROM public."user" WHERE id IN ($ids)');
  }

  LedgerEvidence evidence({double count = 1, String key = sourceKey}) =>
      LedgerEvidence(
        subjectId: aliceId,
        objectId: bobId,
        kind: TrustEvidenceKind.vouch,
        count: count,
        sourceKey: key,
      );

  Future<int> rowCount() async {
    final rows = await db
        .customSelect(
          'SELECT count(*)::int AS n FROM public.trust_evidence '
          "WHERE subject_user_id = '$aliceId'",
        )
        .get();
    return rows.single.read<int>('n');
  }

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = openDisposablePgDatabase(target);
      repo = TrustLedgerRepository(db);
    });

    setUp(() async {
      await cleanup();
      for (final id in [aliceId, bobId]) {
        await db.customStatement(
          'INSERT INTO public."user" '
          '(id, display_name, public_key, created_at, updated_at) '
          "VALUES ('$id', '$id', 'pk-$id', now(), now())",
        );
      }
    });

    tearDown(cleanup);

    tearDownAll(() async {
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });
  }

  test(
    'duplicate source_key is a no-op',
    () async {
      await repo.record([evidence()]);
      await repo.record([evidence(count: 5)]);
      expect(await rowCount(), 1);
    },
    skip: skipReason,
  );

  test(
    'duplicate source_key inside one batch keeps a single row',
    () async {
      await repo.record([evidence(), evidence(count: 2)]);
      expect(await rowCount(), 1);
    },
    skip: skipReason,
  );

  test(
    'a foreign-key violation still raises',
    () async {
      await expectLater(
        repo.record([
          const LedgerEvidence(
            subjectId: 'Utlcghost00001',
            objectId: bobId,
            kind: TrustEvidenceKind.vouch,
            count: 1,
            sourceKey: 'trust_ledger_conflict:ghost',
          ),
        ]),
        throwsA(anything),
      );
      expect(await rowCount(), 0);
    },
    skip: skipReason,
  );
}
