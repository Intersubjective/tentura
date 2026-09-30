@Tags(['pg'])
library;

import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/trust_evidence_repository.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/review_close_snapshot.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/review_finalization_test_support.dart' as support;
import '../../support/pg_test_public_keys.dart';

/// End-to-end forward finalization with real TrustEvidenceRepository (pg).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_OUTCOME_FINALIZATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fof',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late TrustEvidenceRepository trustRepo;

  const beaconId = 'Bfofin00001';
  const authorId = 'UfofAuthor01';
  const committerId = 'UfofCommit01';
  const forwarderId = 'UfofForward1';
  const allIds = [authorId, committerId, forwarderId];

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = openDisposablePgDatabase(target);
      trustRepo = TrustEvidenceRepository(db);
      for (var i = 0; i < allIds.length; i++) {
        await db.customStatement(
          '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('${allIds[i]}', '${allIds[i]}', '${pgTestPublicKey('fof', i + 1)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        );
      }
    });

    tearDown(() async {
      final idList = allIds.map((id) => "'$id'").join(', ');
      await db.customStatement(
        "DELETE FROM public.trust_evidence "
        "WHERE beacon_id = '$beaconId' "
        "OR subject_user_id IN ($idList) "
        "OR object_user_id IN ($idList)",
      );
      await db.customStatement(
        "DELETE FROM public.user_trust_edge "
        "WHERE subject IN ($idList) OR object IN ($idList)",
      );
    });

    tearDownAll(() async {
      final idList = allIds.map((id) => "'$id'").join(', ');
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ($idList)''',
      );
      await tearDownDisposablePgWriter(session: session, drift: db);
    });
  }

  test('closeAndFinalize persists forward ledger rows in Postgres', () async {
    final evalRepo = support.FakeEvaluationRepo()
      ..authorParticipantId = authorId
      ..committerParticipantId = committerId;
    final forwardEdges = support.FakeForwardEdges();
    final helpOffers = support.FakeHelpOffers();

    forwardEdges.edges = [
      ForwardEdgeEntity(
        id: 'Ffof1',
        beaconId: beaconId,
        senderId: authorId,
        recipientId: forwarderId,
        createdAt: DateTime.utc(2026, 1, 2),
        batchId: 'Bfof1',
      ),
      ForwardEdgeEntity(
        id: 'Ffof2',
        beaconId: beaconId,
        senderId: forwarderId,
        recipientId: committerId,
        createdAt: DateTime.utc(2026, 1, 3),
        parentEdgeId: 'Ffof1',
        batchId: 'Bfof2',
      ),
    ];
    helpOffers.offers = [
      HelpOfferEntity(
        beaconId: beaconId,
        userId: committerId,
        createdAt: DateTime.utc(2026, 1, 5),
        updatedAt: DateTime.utc(2026, 1, 5),
      ),
    ];
    evalRepo.snapshotOnClose = ReviewCloseSnapshot(
      beaconId: beaconId,
      beaconAuthorId: authorId,
      beaconTitle: 'Forward finalize request',
      windowOpenedAt: DateTime.utc(2026, 1, 1),
      finalizedEvaluations: [
        const FinalizedEvaluation(
          evaluatorId: authorId,
          evaluatedUserId: committerId,
          value: 5,
          role: 0,
        ),
      ],
    );

    final case_ = support.buildReviewFinalizationCase(
      evaluationRepo: evalRepo,
      forwardEdges: forwardEdges,
      helpOffers: helpOffers,
      trustEvidence: trustRepo,
    );

    final result = await case_.closeAndFinalize(beaconId, reason: 'test');
    expect(result.didClose, isTrue);

    final forwardRows = await db.customSelect(
      '''
SELECT COUNT(*)::int AS c FROM public.trust_evidence
WHERE beacon_id = '$beaconId' AND kind = 5
''',
    ).getSingle();
    expect(forwardRows.read<int>('c'), greaterThan(0));

    expect(await trustRepo.hasForwardEvidenceForRequest(beaconId), isTrue);

    final second = await case_.closeAndFinalize(beaconId, reason: 'retry');
    expect(second.didClose, isTrue);
    final afterRetry = await db.customSelect(
      '''
SELECT COUNT(*)::int AS c FROM public.trust_evidence
WHERE beacon_id = '$beaconId' AND kind = 5
''',
    ).getSingle();
    expect(afterRetry.read<int>('c'), forwardRows.read<int>('c'));
  }, skip: skipReason);
}
