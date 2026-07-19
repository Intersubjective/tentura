@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/trust_evidence_repository.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_context.dart';
import 'package:tentura_server/domain/trust/trust_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_metadata.dart';
import 'package:tentura_server/domain/trust/trust_source_type.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasLedger(probe)) {
        skipReason = 'trust_evidence_event missing (m0122 not applied)';
      }
    } finally {
      await probe.close();
    }
  }

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
        : "request_id = '$request'";
    final row = await db.customSelect(
      'SELECT COUNT(*)::int AS c FROM trust_evidence_event WHERE $filter',
    ).getSingle();
    return row.read<int>('c');
  }

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      repo = TrustEvidenceRepository(db);
      for (final id in allIds) {
        await user(id);
      }
    });

    tearDown(() async {
      await db.customStatement('''
DELETE FROM public.trust_evidence_event
WHERE subject_user_id IN ('$aliceId', '$bobId')
   OR object_user_id IN ('$aliceId', '$bobId');
DELETE FROM public.user_trust_source_edge
WHERE subject IN ('$aliceId', '$bobId') OR object IN ('$aliceId', '$bobId');
DELETE FROM public.user_trust_edge
WHERE subject IN ('$aliceId', '$bobId') OR object IN ('$aliceId', '$bobId');
''');
    });

    tearDownAll(() async {
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ('$aliceId', '$bobId')''',
      );
      await db.close();
    });
  }

  test('record writes ledger row and bumps source', () async {
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
    final source = await db.customSelect(
      "SELECT s_good FROM user_trust_source_edge WHERE trust_context = 'personal' AND subject = '$aliceId'",
    ).getSingleOrNull();
    expect(source, isNotNull);
    expect(source!.read<double>('s_good'), greaterThan(0));
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

  test('both propagated source types can coexist on one request pair', () async {
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
    expect(await ledgerCount(request: requestId), 2);
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
    final row = await db.customSelect(
      "SELECT metadata::text AS m FROM trust_evidence_event WHERE request_id = '$requestId' LIMIT 1",
    ).getSingle();
    final json = row.read<String>('m');
    expect(json, contains('algorithm_version'));
    expect(json, contains('supporting_commitment_ids'));
    expect(json, isNot(contains('display_name')));
    expect(json, isNot(contains('mass')));
  }, skip: skipReason);

  test('hasForwardEvidenceForRequest reflects forward context rows', () async {
    expect(await repo.hasForwardEvidenceForRequest(requestId), isFalse);
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
            sourceType: TrustSourceType.unsuccessfulRequestForward,
            requestId: requestId,
          ),
        ],
      ),
    );
    expect(await repo.hasForwardEvidenceForRequest(requestId), isTrue);
  }, skip: skipReason);
}

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? 'localhost',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgDatabase: Platform.environment['POSTGRES_DBNAME'] ?? 'postgres',
  pgUsername: Platform.environment['POSTGRES_USERNAME'] ?? 'postgres',
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  genealogyNodeKeySecret: 'test-genealogy-secret',
);

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _hasLedger(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT count(*)::int > 0 AS ok FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'trust_evidence_event'
''',
  ).getSingle();
  return row.read<bool>('ok');
}
