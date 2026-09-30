@Tags(['pg'])
library;

import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/trust_evidence_repository.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_context.dart';
import 'package:tentura_server/domain/trust/trust_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_metadata.dart';
import 'package:tentura_server/domain/trust/trust_source_type.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TRUST_EVIDENCE_WRITER_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_tew',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late TrustEvidenceRepository repo;

  const aliceId = 'UtewAlice001';
  const bobId = 'UtewBob00001';
  const requestId = 'Btewrequest01';
  const allIds = [aliceId, bobId];

  Future<void> user(String id) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', '${pgTestPublicKey('tew', allIds.indexOf(id) + 1)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<int> ledgerCount({String? request}) async {
    final filter = request == null
        ? "subject_user_id IN ('$aliceId', '$bobId')"
        : "beacon_id = '$request'";
    final row = await db
        .customSelect(
          'SELECT COUNT(*)::int AS c FROM public.trust_evidence WHERE $filter',
        )
        .getSingle();
    return row.read<int>('c');
  }

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = openDisposablePgDatabase(target);
      repo = TrustEvidenceRepository(db);
      for (final id in allIds) {
        await user(id);
      }
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.trust_evidence "
        "WHERE subject_user_id IN ('$aliceId', '$bobId') "
        "OR object_user_id IN ('$aliceId', '$bobId')",
      );
      await db.customStatement(
        "DELETE FROM public.user_trust_edge "
        "WHERE subject IN ('$aliceId', '$bobId') OR object IN ('$aliceId', '$bobId')",
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: db);
    });
  }

  test('record writes ledger row and projects the pair', () async {
    await repo.record(
      TrustEvidenceBatch(
        sourceUserId: aliceId,
        at: DateTime.utc(2026, 2, 1),
        items: [
          TrustEvidence(
            targetUserId: bobId,
            bin: TrustBin.good,
            count: 1,
            context: TrustContext.personal,
            sourceType: TrustSourceType.userVote,
            sourceId: 'vote:1',
          ),
        ],
      ),
    );
    expect(await ledgerCount(), 1);
    final edge = await db
        .customSelect(
          "SELECT trust_w FROM public.user_trust_edge "
          "WHERE subject = '$aliceId' AND object = '$bobId'",
        )
        .getSingleOrNull();
    expect(edge, isNotNull);
    expect(edge!.read<double>('trust_w'), greaterThan(0));
  }, skip: skipReason);

  test('duplicate propagated bin is idempotent', () async {
    final item = TrustEvidence(
      targetUserId: bobId,
      bin: TrustBin.good,
      count: 1,
      context: TrustContext.forward,
      sourceType: TrustSourceType.propagatedAuthorEvaluatedCommitment,
      requestId: requestId,
      sourceId: 'prop:1',
      metadata: const TrustEvidenceMetadata(algorithmVersion: 1),
    );
    final batch = TrustEvidenceBatch(
      sourceUserId: aliceId,
      at: DateTime.utc(2026, 2, 1),
      items: [item],
    );
    await repo.record(batch);
    await repo.record(batch);
    expect(await ledgerCount(request: requestId), 1);
  }, skip: skipReason);

  test('positive evidence from different source types coexists', () async {
    await repo.record(
      TrustEvidenceBatch(
        sourceUserId: aliceId,
        at: DateTime.utc(2026, 2, 1),
        items: [
          TrustEvidence(
            targetUserId: bobId,
            bin: TrustBin.good,
            count: 1,
            context: TrustContext.forward,
            sourceType: TrustSourceType.propagatedAuthorEvaluatedCommitment,
            requestId: requestId,
            sourceId: 'prop:eval',
          ),
          TrustEvidence(
            targetUserId: bobId,
            bin: TrustBin.good,
            count: 1,
            context: TrustContext.forward,
            sourceType: TrustSourceType.unsuccessfulRequestForward,
            requestId: requestId,
            sourceId: 'prop:other',
          ),
        ],
      ),
    );
    expect(await ledgerCount(request: requestId), 2);
  }, skip: skipReason);

  test('no-effect evidence gets no ledger row (phase A)', () async {
    await repo.record(
      TrustEvidenceBatch(
        sourceUserId: aliceId,
        at: DateTime.utc(2026, 2, 1),
        items: [
          TrustEvidence(
            targetUserId: bobId,
            bin: TrustBin.noEffect,
            count: 1,
            context: TrustContext.forward,
            sourceType: TrustSourceType.negativeCommitmentRouteNoEffect,
            requestId: requestId,
            sourceId: 'prop:route',
          ),
        ],
      ),
    );
    expect(await ledgerCount(request: requestId), 0);
  }, skip: skipReason);

  test('metadata stores only constrained keys', () async {
    await repo.record(
      TrustEvidenceBatch(
        sourceUserId: aliceId,
        at: DateTime.utc(2026, 2, 1),
        items: [
          TrustEvidence(
            targetUserId: bobId,
            bin: TrustBin.good,
            count: 1,
            context: TrustContext.forward,
            sourceType: TrustSourceType.propagatedAuthorEvaluatedCommitment,
            requestId: requestId,
            metadata: const TrustEvidenceMetadata(
              algorithmVersion: 2,
              supportingCommitmentIds: ['c1'],
            ),
          ),
        ],
      ),
    );
    final row = await db
        .customSelect(
          "SELECT metadata::text AS m FROM public.trust_evidence WHERE beacon_id = '$requestId' LIMIT 1",
        )
        .getSingle();
    final json = row.read<String>('m');
    expect(json, contains('algorithm_version'));
    expect(json, contains('supporting_commitment_ids'));
    expect(json, isNot(contains('display_name')));
    expect(json, isNot(contains('mass')));
  }, skip: skipReason);

  test('hasForwardEvidenceForRequest reflects forward ledger rows', () async {
    expect(await repo.hasForwardEvidenceForRequest(requestId), isFalse);
    await repo.record(
      TrustEvidenceBatch(
        sourceUserId: aliceId,
        at: DateTime.utc(2026, 2, 1),
        items: [
          TrustEvidence(
            targetUserId: bobId,
            bin: TrustBin.good,
            count: 1,
            context: TrustContext.forward,
            sourceType: TrustSourceType.propagatedAuthorEvaluatedCommitment,
            requestId: requestId,
          ),
        ],
      ),
    );
    expect(await repo.hasForwardEvidenceForRequest(requestId), isTrue);
  }, skip: skipReason);
}
