@Tags(['pg', 'mr'])
library;

import 'dart:math' as math;

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
import 'package:tentura_server/data/repository/capability_own_evidence_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/pair_block_query_repository.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/routing_mute_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/capability_projection_case.dart';
import 'package:tentura_server/domain/use_case/forward_band_case.dart';

import '../../support/disposable_pg_target.dart';

// Alice is the third person who forwards; Bob gives Carol (and Dave) tags.
const _alice = 'Ulblseedali1';
const _bob = 'Ulblseedbob1';
const _carol = 'Ulblseedcar1';
const _dave = 'Ulblseeddav1';
const _beaconId = 'Blblseedbcn1';
const _ctx = '';
const _tag = 'transport';
const _otherTag = 'pets';

const _allIds = [_alice, _bob, _carol, _dave];

/// ADR 0012 D5/D19 (issue #897): every tag a person gives someone is a routing
/// seed. A private label aggregates exactly like a seed attestation (seed
/// weight, 90-day horizon, θ_seed); one tag given through both sources counts
/// once; commit roles still never aggregate.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_LABEL_SEED_TEST_DB',
    defaultNamePrefix: 'tentura_test_label_seed',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('private labels feed Forward suggestions as routing seeds', () {
    late Connection writer;
    late TenturaDb database;
    var databaseReady = false;
    var writerReady = false;
    late MeritrankRepository meritRank;
    late ForwardBandCase forwardBandCase;
    late CapabilityCase capabilityCase;
    late PersonCapabilityEventRepository labelRepo;
    late CapabilityCellRepository cellRepo;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgcrypto');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      writerReady = true;
      await migrateDbSchema(writer);

      final env = target.databaseEnv;
      final logger = Logger('PrivateLabelRoutingSeedPgTest');
      database = TenturaDb(env);
      databaseReady = true;

      meritRank = MeritrankRepository(database);
      final witnessWindowRepo = WitnessWindowRepository(database);
      cellRepo = CapabilityCellRepository(database);
      final userBlockRepo = UserBlockRepository(
        env,
        database,
        witnessWindow: witnessWindowRepo,
      );
      final projectionCase = CapabilityProjectionCase(
        witnessWindowRepo,
        cellRepo,
        CapabilityOwnEvidenceRepository(database),
        RoutingMuteRepository(database),
        PairBlockQueryRepository(database),
        PersonVisibilityRepository(database),
        userBlockRepo,
        env: env,
        logger: logger,
      );
      final forwardEdgeRepo = ForwardEdgeRepository(database);
      forwardBandCase = ForwardBandCase(
        BandCandidateRepository(
          database,
          forwardEdgeRepo,
          HelpOfferRepository(database),
          InboxRepository(database),
        ),
        BeaconRepository(database),
        projectionCase,
        BeaconAccessRepository(database),
        env: env,
        logger: logger,
      );

      labelRepo = PersonCapabilityEventRepository(database);
      capabilityCase = CapabilityCase(labelRepo, env: env, logger: logger);
    });

    setUp(() async {
      await _cleanup(database);
      for (final id in _allIds) {
        await _insertUser(database, id);
      }
      await _seedTrustGraph(database, meritRank);
      await _seedBeacon(writer);
    });

    tearDownAll(() async {
      if (databaseReady) {
        await _cleanup(database);
        await database.close();
      }
      if (writerReady) await writer.close();
      await target.drop();
    });

    test(
      "a tag Bob gives Carol on her profile shows in Alice's Forward "
      'suggestions as a network seed',
      () async {
        final before = await forwardBandCase.composeBand(
          egoId: _alice,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );
        expect(
          _carolSeedLabels(before),
          isEmpty,
          reason: 'fixture: nobody has tagged Carol yet',
        );

        // The profile «Edit» dialog path (capabilitySetViewerVisible).
        await capabilityCase.setViewerVisible(
          observerId: _bob,
          subjectId: _carol,
          slugs: const [_tag],
        );

        final band = await forwardBandCase.composeBand(
          egoId: _alice,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );
        expect(
          _carolSeedLabels(band),
          contains(_tag),
          reason:
              "Bob's tag for Carol must reach Alice's Forward band under "
              'the seed rules',
        );
      },
      skip: skipReason,
    );

    test(
      'a tag Bob removes from Carol stops feeding Forward suggestions',
      () async {
        await capabilityCase.setViewerVisible(
          observerId: _bob,
          subjectId: _carol,
          slugs: const [_tag],
        );
        final withTag = await forwardBandCase.composeBand(
          egoId: _alice,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );
        expect(_carolSeedLabels(withTag), contains(_tag));

        await capabilityCase.setViewerVisible(
          observerId: _bob,
          subjectId: _carol,
          slugs: const [],
        );
        final withoutTag = await forwardBandCase.composeBand(
          egoId: _alice,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );
        expect(_carolSeedLabels(withoutTag), isNot(contains(_tag)));
      },
      skip: skipReason,
    );

    test(
      'a 90-day-old tag weighs exactly like a 90-day-old seed attestation '
      '(seed half-life, never outcome strength)',
      () async {
        // Carol: a profile tag from Bob. Dave: a legacy invite-seed
        // attestation from Bob. Both backdated by one seed half-life.
        await labelRepo.upsertPrivateLabels(
          observerId: _bob,
          subjectId: _carol,
          slugs: const [_tag],
        );
        await _insertLegacySeedAttestation(
          writer,
          observerId: _bob,
          subjectId: _dave,
          tagSlug: _tag,
        );
        await writer.execute(
          Sql.named('''
UPDATE public.person_capability_event
SET created_at = now() - interval '90 days'
WHERE observer_user_id = @observer
  AND subject_user_id IN (@carol, @dave)
  AND tag_slug = @tag
'''),
          parameters: {
            'observer': _bob,
            'carol': _carol,
            'dave': _dave,
            'tag': _tag,
          },
        );
        await _rebuild(cellRepo, _bob, _carol, _tag);
        await _rebuild(cellRepo, _bob, _dave, _tag);

        final cells = await _bobCells(cellRepo, [_carol, _dave], [_tag]);
        final carol = _cellFor(cells, _carol, _tag);
        final dave = _cellFor(cells, _dave, _tag);

        expect(dave, isNotNull, reason: 'fixture: legacy seed is counted');
        expect(
          carol,
          isNotNull,
          reason: "Bob's tag for Carol must aggregate as a seed",
        );
        expect(carol!.eSeed, closeTo(dave!.eSeed, 1e-6));
        expect(carol.eSeed, greaterThan(0));
        expect(
          carol.eOut,
          0,
          reason: 'a tag is a routing seed, never outcome evidence',
        );
      },
      skip: skipReason,
    );

    test(
      'the same tag given both as a label and as a seed attestation counts '
      'once',
      () async {
        // Carol: legacy invite-seed attestation AND a profile tag, same slug.
        // Dave: the profile tag alone.
        await _insertLegacySeedAttestation(
          writer,
          observerId: _bob,
          subjectId: _carol,
          tagSlug: _tag,
        );
        await capabilityCase.setViewerVisible(
          observerId: _bob,
          subjectId: _carol,
          slugs: const [_tag],
        );
        await capabilityCase.setViewerVisible(
          observerId: _bob,
          subjectId: _dave,
          slugs: const [_tag],
        );
        await _rebuild(cellRepo, _bob, _carol, _tag);
        await _rebuild(cellRepo, _bob, _dave, _tag);

        final cells = await _bobCells(cellRepo, [_carol, _dave], [_tag]);
        final carol = _cellFor(cells, _carol, _tag);
        final dave = _cellFor(cells, _dave, _tag);

        expect(dave, isNotNull, reason: 'a lone tag aggregates as a seed');
        expect(carol, isNotNull);
        expect(dave!.eSeed, greaterThan(0));
        expect(
          carol!.eSeed,
          closeTo(dave.eSeed, 1e-6),
          reason:
              'one observer+subject+slug under both sources is one seed, '
              'not two',
        );
      },
      skip: skipReason,
    );

    test(
      'a tag given both as a label and as a seed attestation counts once in '
      "Alice's Forward suggestions",
      () async {
        // Dave becomes a Forward candidate for Alice too.
        await _trustEdge(database, _alice, _dave);
        await _trustEdge(database, _dave, _alice);
        await meritRank.putEdge(nodeA: _alice, nodeB: _dave, weight: 0.7);
        await meritRank.putEdge(nodeA: _dave, nodeB: _alice, weight: 0.65);

        // Materialise Alice's witness window and read Bob's weight in it.
        await forwardBandCase.composeBand(
          egoId: _alice,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );
        final m = await _bobWeightForAlice(writer);
        expect(
          m,
          greaterThan(kCapThetaSeed),
          reason: 'fixture: Bob must be an admitted witness for Alice',
        );

        // One seed of decayed mass x yields S_seed = m·x/(1+x). x1 is the
        // mass at which one seed just reaches θ_seed. Carol's two records
        // each carry 0.75·x1: counted once they stay below θ_seed, counted
        // twice (1.5·x1) they clear it. Dave's lone tag carries 1.5·x1, so a
        // single tag of the doubled mass does show.
        final c = kCapThetaSeed / m;
        final x1 = c / (1 - c);
        final carolAge = _ageForMass(0.75 * x1);
        final daveAge = _ageForMass(1.5 * x1);

        await _insertLegacySeedAttestation(
          writer,
          observerId: _bob,
          subjectId: _carol,
          tagSlug: _tag,
        );
        await capabilityCase.setViewerVisible(
          observerId: _bob,
          subjectId: _carol,
          slugs: const [_tag],
        );
        await capabilityCase.setViewerVisible(
          observerId: _bob,
          subjectId: _dave,
          slugs: const [_tag],
        );
        await _backdate(writer, subjectId: _carol, ageSeconds: carolAge);
        await _backdate(writer, subjectId: _dave, ageSeconds: daveAge);
        await _rebuild(cellRepo, _bob, _carol, _tag);
        await _rebuild(cellRepo, _bob, _dave, _tag);

        final band = await forwardBandCase.composeBand(
          egoId: _alice,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );
        expect(
          _seedLabelsFor(band, _dave),
          contains(_tag),
          reason: "Bob's lone tag for Dave must reach Alice's Forward band",
        );
        expect(
          _seedLabelsFor(band, _carol),
          isNot(contains(_tag)),
          reason:
              "Bob's one tag for Carol, recorded as both a label and a seed "
              'attestation, must count once and stay below θ_seed',
        );
      },
      skip: skipReason,
    );

    test(
      'a tag Bob hid from Carol is not listed among the tags Bob gave her',
      () async {
        // Bob hides an automatic tag; the hide is stored as a tombstone.
        await labelRepo.insertTombstone(
          observerId: _bob,
          subjectId: _carol,
          slug: _otherTag,
        );
        await capabilityCase.setViewerVisible(
          observerId: _bob,
          subjectId: _carol,
          slugs: const [_tag],
        );

        expect(
          await capabilityCase.getPrivateLabelsForUser(
            observerId: _bob,
            subjectId: _carol,
          ),
          [_tag],
        );
        final cues = await capabilityCase.getCapabilityCues(
          viewerId: _bob,
          subjectId: _carol,
        );
        expect(cues.privateLabels, [_tag]);
      },
      skip: skipReason,
    );

    test('commit roles still never aggregate', () async {
      await labelRepo.insertCommitRole(
        observerId: _bob,
        subjectId: _carol,
        beaconId: _beaconId,
        slug: _otherTag,
      );
      await _rebuild(cellRepo, _bob, _carol, _otherTag);

      final cells = await _bobCells(cellRepo, [_carol], [_otherTag]);
      expect(_cellFor(cells, _carol, _otherTag), isNull);
    }, skip: skipReason);
  });
}

List<String> _carolSeedLabels(List<ForwardBandRow> band) =>
    _seedLabelsFor(band, _carol);

List<String> _seedLabelsFor(List<ForwardBandRow> band, String userId) => [
  for (final row in band.where((r) => r.userId == userId && !r.isExploration))
    for (final label in row.labels)
      if (label.tier == ProjectionTier.networkSeed) label.tagSlug,
];

/// Age (seconds) at which one seed's decayed mass is [mass] under the seed
/// half-life.
int _ageForMass(double mass) =>
    (-kCapHalfLifeSeedSeconds * math.log(mass) / math.ln2).round();

Future<double> _bobWeightForAlice(Connection writer) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT m FROM public.ego_witness_window
WHERE ego_user_id = @ego AND witness_user_id = @witness AND admitted
'''),
    parameters: {'ego': _alice, 'witness': _bob},
  );
  expect(rows, hasLength(1), reason: "fixture: Bob in Alice's window");
  return (rows.single[0]! as num).toDouble();
}

Future<void> _backdate(
  Connection writer, {
  required String subjectId,
  required int ageSeconds,
}) => writer.execute(
  Sql.named('''
UPDATE public.person_capability_event
SET created_at = now() - make_interval(secs => @age)
WHERE observer_user_id = @observer
  AND subject_user_id = @subject
  AND tag_slug = @tag
'''),
  parameters: {
    'age': ageSeconds.toDouble(),
    'observer': _bob,
    'subject': subjectId,
    'tag': _tag,
  },
);

Future<void> _rebuild(
  CapabilityCellRepository cellRepo,
  String observer,
  String subject,
  String tag,
) => cellRepo.rebuildCell(
  CellRef(observerUserId: observer, subjectUserId: subject, tagSlug: tag),
);

Future<List<WitnessCellRow>> _bobCells(
  CapabilityCellRepository cellRepo,
  List<String> subjectIds,
  List<String> tagSlugs,
) => cellRepo.fetchCells(
  subjectIds: subjectIds,
  tagSlugs: tagSlugs,
  admittedWitnesses: const [
    WitnessWeight(witnessUserId: _bob, m: 1, admitted: true),
  ],
);

WitnessCellRow? _cellFor(
  List<WitnessCellRow> cells,
  String subjectId,
  String tagSlug,
) {
  for (final cell in cells) {
    if (cell.subjectUserId == subjectId && cell.tagSlug == tagSlug) {
      return cell;
    }
  }
  return null;
}

/// A `seedRoutingAttestation` row as written before labels and seeds merged;
/// the source value stays for history (ADR 0012 change log).
Future<void> _insertLegacySeedAttestation(
  Connection writer, {
  required String observerId,
  required String subjectId,
  required String tagSlug,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.person_capability_event (
  id, subject_user_id, observer_user_id, tag_slug, source_type, visibility
) VALUES (@id, @subject, @observer, @tag, 4, 0)
'''),
  parameters: {
    'id': 'CElblseed${subjectId.substring(subjectId.length - 4)}$tagSlug',
    'subject': subjectId,
    'observer': observerId,
    'tag': tagSlug,
  },
);

Future<void> _cleanup(TenturaDb db) async {
  for (final a in _allIds) {
    for (final b in _allIds) {
      if (a == b) continue;
      await db.customStatement(
        "SELECT mr_put_edge('$a', '$b', 0::double precision, ''::text, 0)",
      );
    }
  }
  final idList = _allIds.map((id) => "'$id'").join(', ');
  for (final table in [
    'capability_evidence_edge',
    'capability_evidence_generation',
    'person_capability_event',
  ]) {
    await db.customStatement(
      'DELETE FROM public.$table '
      'WHERE observer_user_id IN ($idList) OR subject_user_id IN ($idList)',
    );
  }
  const votes = 'DELETE FROM public.vote_user';
  final witnessWindow =
      'DELETE FROM public.ego_witness_window '
      'WHERE ego_user_id IN ($idList) OR witness_user_id IN ($idList)';
  final statements = <String>[
    'DELETE FROM public.capability_routing_mute WHERE user_id IN ($idList)',
    witnessWindow,
    "DELETE FROM public.beacon WHERE id = '$_beaconId'",
    '$votes WHERE subject IN ($idList) OR object IN ($idList)',
    'DELETE FROM public."user" WHERE id IN ($idList)',
  ];
  for (final sql in statements) {
    await db.customStatement(sql);
  }
}

Future<void> _seedTrustGraph(
  TenturaDb db,
  MeritrankRepository meritRank,
) async {
  // Alice and Carol know each other, so Carol is a Forward candidate for
  // Alice; Alice trusts Bob, so Bob is one of Alice's admitted witnesses.
  await _trustEdge(db, _alice, _carol);
  await _trustEdge(db, _carol, _alice);
  await meritRank.putEdge(nodeA: _alice, nodeB: _carol, weight: 0.7);
  await meritRank.putEdge(nodeA: _carol, nodeB: _alice, weight: 0.65);

  await _trustEdge(db, _alice, _bob);
  await meritRank.putEdge(nodeA: _alice, nodeB: _bob, weight: 0.85);
}

Future<void> _seedBeacon(Connection writer) => writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, needs, primary_need_slug, status
) VALUES (
  '$_beaconId',
  '$_bob',
  'Label seed routing beacon',
  'd',
  '$_tag',
  '$_tag',
  ${BeaconStatus.reviewOpen.smallintValue}
)
ON CONFLICT (id) DO NOTHING
''');

Future<void> _trustEdge(TenturaDb db, String subject, String object) =>
    db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

Future<void> _insertUser(TenturaDb db, String id) => db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');
