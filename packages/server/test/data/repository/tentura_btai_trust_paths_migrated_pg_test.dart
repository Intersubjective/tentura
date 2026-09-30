// tentura-btai: production trust paths must run on the post-m0202 schema.
@Tags(['pg'])
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/trust_evidence_repository.dart';
import 'package:tentura_server/data/repository/user_trust_edge_repository.dart';
import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_context.dart';
import 'package:tentura_server/domain/trust/trust_evidence.dart';
import 'package:tentura_server/domain/trust/trust_source_type.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// `cutoverBackfillIfNeeded` never touches MeritRank.
class _UnusedMeritrank implements MeritrankRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected MeritRank call: ${invocation.memberName}');
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BTAI_TRUST_PATHS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_btai',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  // The acceptance run sets TENTURA_REQUIRE_PG_TESTS=1: an unreachable
  // Postgres is then a failure, never a silent skip. Optional local runs
  // leave it unset and keep the skip.
  final pgRequired = Platform.environment['TENTURA_REQUIRE_PG_TESTS'] == '1';

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late TrustEvidenceRepository evidenceRepo;
  late UserTrustEdgeRepository edgeRepo;

  const aliceId = 'UbtaiAlice01';
  const bobId = 'UbtaiBob0001';
  const allIds = [aliceId, bobId];

  Future<void> user(String id) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', '${pgTestPublicKey('btai', allIds.indexOf(id) + 1)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  TrustEvidenceBatch batch() => TrustEvidenceBatch(
    sourceUserId: aliceId,
    at: DateTime.utc(2026, 1, 2),
    items: [
      const TrustEvidence(
        targetUserId: bobId,
        bin: TrustBin.good,
        count: kTrustVoteEvidenceCount,
        context: TrustContext.personal,
        sourceType: TrustSourceType.userVote,
      ),
    ],
  );

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = openDisposablePgDatabase(target);
      evidenceRepo = TrustEvidenceRepository(db);
      edgeRepo = UserTrustEdgeRepository(
        db,
        _UnusedMeritrank(),
        evidenceRepo,
      );
      for (final id in allIds) {
        await user(id);
      }
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.vote_user WHERE subject IN ('$aliceId', '$bobId')",
      );
      await db.customStatement(
        "DELETE FROM public.user_trust_edge "
        "WHERE subject IN ('$aliceId', '$bobId')",
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: db);
    });
  }

  test('Postgres is reachable when the run requires it', () {
    if (pgRequired) {
      expect(
        reachable,
        isTrue,
        reason:
            'TENTURA_REQUIRE_PG_TESTS=1 but the Postgres admin database is '
            'not reachable; skipped pg tests do not count as coverage',
      );
    }
  });

  test(
    'disposable database is migrated through m0202 and its ledger objects',
    () async {
      final version = await session.writer.execute(
        'SELECT max(version) FROM public.schema_version',
      );
      expect(
        (version.single.single! as String).compareTo('0202'),
        greaterThanOrEqualTo(0),
        reason: 'schema_version must be at or past m0202',
      );

      final objects = await session.writer.execute(r'''
SELECT
  to_regclass('public.trust_evidence') IS NOT NULL AS has_ledger,
  to_regclass('public.trust_evidence_event') IS NULL AS legacy_ledger_gone,
  to_regclass('public.user_trust_source_edge') IS NULL AS source_edge_gone,
  NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'trust_rebuild_effective_edge'
  ) AS rebuild_fn_gone
''');
      expect(objects.single.toList(), [true, true, true, true]);
    },
    skip: skipReason,
  );

  group('TrustEvidenceRepository.record on the migrated schema', () {
    test(
      'records a personal evidence batch without touching dropped objects',
      () async {
        await evidenceRepo.record(batch());
      },
      skip: skipReason,
    );

    test(
      'projects the recorded pair onto user_trust_edge',
      () async {
        await evidenceRepo.record(batch());

        final row = await db
            .customSelect(
              'SELECT trust_w FROM public.user_trust_edge '
              'WHERE subject = \$1 AND object = \$2',
              variables: [
                Variable<String>(aliceId),
                Variable<String>(bobId),
              ],
            )
            .getSingleOrNull();
        expect(row, isNotNull, reason: 'evidence must reach the projection');
        expect(row!.read<double>('trust_w'), greaterThan(0));
      },
      skip: skipReason,
    );
  });

  group('UserTrustEdgeRepository.cutoverBackfillIfNeeded on the migrated schema',
      () {
    test(
      'completes on an empty database',
      () async {
        await edgeRepo.cutoverBackfillIfNeeded();
      },
      skip: skipReason,
    );

    test(
      'backfills an existing vote into the trust projection',
      () async {
        await db.customStatement(
          "INSERT INTO public.vote_user (subject, object, amount) "
          "VALUES ('$aliceId', '$bobId', 1)",
        );

        await edgeRepo.cutoverBackfillIfNeeded();

        final row = await db
            .customSelect(
              'SELECT trust_w FROM public.user_trust_edge '
              'WHERE subject = \$1 AND object = \$2',
              variables: [
                Variable<String>(aliceId),
                Variable<String>(bobId),
              ],
            )
            .getSingleOrNull();
        expect(row, isNotNull);
        expect(row!.read<double>('trust_w'), greaterThan(0));
      },
      skip: skipReason,
    );
  });
}
