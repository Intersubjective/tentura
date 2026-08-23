@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/band_candidate_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/capability_cell_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/capability_own_evidence_repository.dart';
import 'package:tentura_server/data/repository/evaluation_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/pair_block_query_repository.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/routing_mute_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/capability/witness_window_policy.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/use_case/capability_projection_case.dart';
import 'package:tentura_server/domain/use_case/forward_band_case.dart';
import 'package:tentura_server/domain/use_case/evaluation/review_finalization_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/review_finalization_test_support.dart';

const _alice = 'Ucapg3alice1';
const _bob = 'Ucapg3bob001';
const _carol = 'Ucapg3carol1';
const _eve = 'Ucapg3eve001';
const _beaconId = 'Bcapg3bcn001';
const _ctx = '';
const _tag = 'transport';

const _allIds = [_alice, _bob, _carol, _eve];

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('ForwardBandCase witness admission integration (G3a)', () {
    late Connection writer;
    late TenturaDb database;
    late Env env;
    late Logger logger;
    late MeritrankRepository meritRank;
    late WitnessWindowRepository witnessWindowRepo;
    late BandCandidateRepository bandCandidateRepo;
    late RoutingMuteRepository routingMuteRepo;
    late ForwardBandCase forwardBandCase;
    late ReviewFinalizationCase finalizationCase;
    late EvaluationRepository evalRepo;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgcrypto');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);

      env = target.databaseEnv;
      logger = Logger('ForwardBandWitnessAdmissionG3aPgTest');
      database = TenturaDb(env);

      meritRank = MeritrankRepository(database);
      witnessWindowRepo = WitnessWindowRepository(database);
      final cellRepo = CapabilityCellRepository(database);
      final ownEvidenceRepo = CapabilityOwnEvidenceRepository(database);
      routingMuteRepo = RoutingMuteRepository(database);
      final pairBlockRepo = PairBlockQueryRepository(database);
      final personVisibilityRepo = PersonVisibilityRepository(database);
      final userBlockRepo = UserBlockRepository(
        env,
        database,
        witnessWindow: witnessWindowRepo,
      );
      final forwardEdgeRepo = ForwardEdgeRepository(database);
      final helpOfferRepo = HelpOfferRepository(database);
      final inboxRepo = InboxRepository(database);
      bandCandidateRepo = BandCandidateRepository(
        database,
        forwardEdgeRepo,
        helpOfferRepo,
        inboxRepo,
      );
      final beaconRepo = BeaconRepository(database);
      final beaconAccess = BeaconAccessRepository(database);

      final projectionCase = CapabilityProjectionCase(
        witnessWindowRepo,
        cellRepo,
        ownEvidenceRepo,
        routingMuteRepo,
        pairBlockRepo,
        personVisibilityRepo,
        userBlockRepo,
        env: env,
        logger: logger,
      );

      forwardBandCase = ForwardBandCase(
        bandCandidateRepo,
        beaconRepo,
        projectionCase,
        beaconAccess,
        env: env,
        logger: logger,
      );

      evalRepo = EvaluationRepository(database);
      final capEvidenceRepo = CapabilityEvidenceRepository(database);
      final unitOfWork = MutatingUnitOfWork(database);
      finalizationCase = ReviewFinalizationCase(
        unitOfWork,
        evalRepo,
        FakeForwardEdges(),
        FakeAttribution(),
        FakeHelpOffers(),
        RecordingTrustEvidence(),
        capEvidenceRepo,
        env: env,
        logger: logger,
      );
    });

    setUp(() async {
      await _cleanup(database, meritRank);
      for (final id in _allIds) {
        await _insertUser(database, id);
      }
      await _seedTrustGraph(database, meritRank);
      await _seedBeaconFixture(writer);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test(
      'witness admission gates Tier B network-outcome band rows per ego',
      () async {
        await evalRepo.submitEvaluationAtomic(
          beaconId: _beaconId,
          evaluatorId: _bob,
          evaluatedUserId: _carol,
          value: BeaconEvaluationValue.pos1,
          reasonTags: const ['quality'],
          note: 'thanks',
          ackTags: const [_tag],
        );
        final closeResult = await finalizationCase.closeAndFinalize(
          _beaconId,
          reason: 'test',
          actorUserId: _bob,
        );
        expect(closeResult.didClose, isTrue);

        final aliceCandidates = await bandCandidateRepo.candidatesFor(
          egoId: _alice,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );
        final eveCandidates = await bandCandidateRepo.candidatesFor(
          egoId: _eve,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );
        final aliceCarol = aliceCandidates
            .where((candidate) => candidate.userId == _carol)
            .toList();
        final eveCarol = eveCandidates.where(
          (candidate) => candidate.userId == _carol,
        );
        expect(aliceCarol, hasLength(1));
        expect(eveCarol, hasLength(1));
        expect(aliceCarol.single.canForwardTo, isTrue);
        expect(eveCarol.single.canForwardTo, isTrue);
        expect(aliceCarol.single.forwardMr, greaterThan(0));
        expect(eveCarol.single.forwardMr, greaterThan(0));

        final aliceWindow = await _loadWitnessWindow(witnessWindowRepo, _alice);
        final eveWindow = await _loadWitnessWindow(witnessWindowRepo, _eve);
        final aliceBob = aliceWindow
            .where((weight) => weight.witnessUserId == _bob)
            .toList();
        final eveBob = eveWindow
            .where((weight) => weight.witnessUserId == _bob)
            .toList();
        expect(aliceBob, hasLength(1));
        expect(aliceBob.single.admitted, isTrue);
        expect(
          eveBob.isEmpty || !eveBob.single.admitted,
          isTrue,
          reason: 'Eve must not admit Bob as witness',
        );

        final aliceBand = await forwardBandCase.composeBand(
          egoId: _alice,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );
        final aliceCarolRow = aliceBand
            .where((row) => row.userId == _carol && !row.isExploration)
            .toList();
        expect(aliceCarolRow, hasLength(1));
        expect(aliceCarolRow.single.rowTier, ProjectionTier.networkOutcome);
        expect(
          aliceCarolRow.single.labels.any(
            (label) =>
                label.tagSlug == _tag &&
                label.tier == ProjectionTier.networkOutcome,
          ),
          isTrue,
        );

        final eveBand = await forwardBandCase.composeBand(
          egoId: _eve,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );
        expect(
          eveBand.any(
            (row) =>
                row.userId == _carol &&
                row.rowTier == ProjectionTier.networkOutcome,
          ),
          isFalse,
        );

        await routingMuteRepo.setMute(
          userId: _carol,
          tagSlug: _tag,
          muted: true,
        );

        final aliceBandAfterMute = await forwardBandCase.composeBand(
          egoId: _alice,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );
        expect(
          aliceBandAfterMute.any(
            (row) =>
                row.userId == _carol &&
                row.rowTier == ProjectionTier.networkOutcome &&
                row.labels.any((label) => label.tagSlug == _tag),
          ),
          isFalse,
        );
      },
      skip: skipReason,
    );
  });
}

Future<List<WitnessWeight>> _loadWitnessWindow(
  WitnessWindowRepository repo,
  String egoId,
) async {
  final cached = await repo.cachedWindow(
    egoId: egoId,
    normalizedContext: _ctx,
  );
  if (cached.isNotEmpty) {
    return cached;
  }

  final facts = await repo.rawWindowFacts(
    egoId: egoId,
    normalizedContext: _ctx,
    topK: kCapWitnessWindowK,
  );
  final weights = computeWitnessWeights(facts);
  await repo.storeWindow(
    egoId: egoId,
    normalizedContext: _ctx,
    weights: weights,
  );
  return weights;
}

Future<void> _seedTrustGraph(
  TenturaDb db,
  MeritrankRepository meritRank,
) async {
  await _trustBothWays(db, _alice, _carol);
  await _trustBothWays(db, _eve, _carol);
  await _mrEdge(meritRank, _alice, _carol, 0.7);
  await _mrEdge(meritRank, _carol, _alice, 0.65);
  await _mrEdge(meritRank, _eve, _carol, 0.7);
  await _mrEdge(meritRank, _carol, _eve, 0.65);

  await _trustEdge(db, _alice, _bob);
  await _mrEdge(meritRank, _alice, _bob, 0.85);
}

Future<void> _seedBeaconFixture(Connection writer) async {
  await writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, needs, primary_need_slug, status
) VALUES (
  'Bcapg3bcn001',
  'Ucapg3bob001',
  'G3a witness admission beacon',
  'd',
  'transport',
  'transport',
  ${BeaconStatus.reviewOpen.smallintValue}
)
ON CONFLICT (id) DO UPDATE SET
  user_id = EXCLUDED.user_id,
  needs = EXCLUDED.needs,
  primary_need_slug = EXCLUDED.primary_need_slug,
  status = EXCLUDED.status
''');

  await writer.execute(r'''
INSERT INTO public.beacon_review_window (
  beacon_id, opened_at, closes_at, status
) VALUES (
  'Bcapg3bcn001',
  now() - interval '1 day',
  now() + interval '7 days',
  0
)
ON CONFLICT (beacon_id) DO UPDATE SET
  opened_at = EXCLUDED.opened_at,
  closes_at = EXCLUDED.closes_at,
  status = EXCLUDED.status
''');

  await writer.execute('''
INSERT INTO public.beacon_evaluation_participant (
  beacon_id, user_id, role, contribution_summary, causal_hint
) VALUES
  (
    'Bcapg3bcn001',
    'Ucapg3bob001',
    ${EvaluationParticipantRole.author.dbValue},
    'authored',
    'hint'
  ),
  (
    'Bcapg3bcn001',
    'Ucapg3carol1',
    ${EvaluationParticipantRole.committer.dbValue},
    'helped',
    'hint'
  )
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon_evaluation_visibility (
  beacon_id, evaluator_id, participant_id
) VALUES (
  'Bcapg3bcn001',
  'Ucapg3bob001',
  'Ucapg3carol1'
)
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon_review_status (beacon_id, user_id, status)
VALUES ('Bcapg3bcn001', 'Ucapg3bob001', 0)
ON CONFLICT DO NOTHING
''');
}

Future<void> _trustBothWays(TenturaDb db, String a, String b) async {
  await _trustEdge(db, a, b);
  await _trustEdge(db, b, a);
}

Future<void> _trustEdge(TenturaDb db, String subject, String object) =>
    db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

Future<void> _mrEdge(
  MeritrankRepository meritRank,
  String subject,
  String object,
  double weight,
) => meritRank.putEdge(nodeA: subject, nodeB: object, weight: weight);

Future<void> _clearMrEdge(
  TenturaDb db,
  String subject,
  String object,
) => db.customStatement(
  "SELECT mr_put_edge('$subject', '$object', 0::double precision, ''::text, 0)",
);

Future<void> _insertUser(TenturaDb db, String id) => db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

Future<void> _cleanup(TenturaDb db, MeritrankRepository meritRank) async {
  for (final ego in [_alice, _eve]) {
    for (final peer in [_bob, _carol, _alice, _eve]) {
      if (ego == peer) continue;
      await _clearMrEdge(db, ego, peer);
      await _clearMrEdge(db, peer, ego);
    }
  }
  await _clearMrEdge(db, _alice, _bob);
  await _clearMrEdge(db, _bob, _alice);

  final idList = _allIds.map((id) => "'$id'").join(', ');
  await db.customStatement(
    'DELETE FROM public.capability_routing_mute WHERE user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.ego_witness_window '
    'WHERE ego_user_id IN ($idList) OR witness_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.person_capability_event '
    'WHERE observer_user_id IN ($idList) OR subject_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.capability_evidence_edge '
    'WHERE observer_user_id IN ($idList) OR subject_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.capability_evidence_generation '
    'WHERE observer_user_id IN ($idList) OR subject_user_id IN ($idList)',
  );
  await db.customStatement(
    "DELETE FROM public.beacon_evaluation_ack_tag WHERE beacon_id = '$_beaconId'",
  );
  await db.customStatement(
    "DELETE FROM public.beacon_evaluation WHERE beacon_id = '$_beaconId'",
  );
  await db.customStatement(
    "DELETE FROM public.beacon_evaluation_participant WHERE beacon_id = '$_beaconId'",
  );
  await db.customStatement(
    "DELETE FROM public.beacon_evaluation_visibility WHERE beacon_id = '$_beaconId'",
  );
  await db.customStatement(
    "DELETE FROM public.beacon_review_status WHERE beacon_id = '$_beaconId'",
  );
  await db.customStatement(
    "UPDATE public.beacon SET status = 0 WHERE id = '$_beaconId'",
  );
  await db.customStatement(
    "DELETE FROM public.beacon_review_window WHERE beacon_id = '$_beaconId'",
  );
  await db.customStatement(
    "DELETE FROM public.beacon WHERE id = '$_beaconId'",
  );
  await db.customStatement(
    'DELETE FROM public.vote_user '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public."user" WHERE id IN ($idList)',
  );
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_G3A_INTEGRATION_TEST_DB'] ??
        'tentura_test_g3a_integration_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_G3A_INTEGRATION_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final admin = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await admin.execute(
        'SELECT pg_terminate_backend(pid) FROM pg_stat_activity '
        "WHERE datname = '$databaseName' AND pid <> pg_backend_pid()",
      );
      await admin.execute('DROP DATABASE IF EXISTS "$databaseName"');
      await admin.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await admin.close();
    }
  }

  Future<void> drop() async {
    final admin = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await admin.execute(
        'SELECT pg_terminate_backend(pid) FROM pg_stat_activity '
        "WHERE datname = '$databaseName' AND pid <> pg_backend_pid()",
      );
      await admin.execute('DROP DATABASE IF EXISTS "$databaseName"');
    } finally {
      await admin.close();
    }
  }
}
