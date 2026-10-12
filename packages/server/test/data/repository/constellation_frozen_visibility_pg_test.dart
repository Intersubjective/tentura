@Tags(['pg', 'mr'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../../support/constellation_anchor_batch_fixture.dart';
import '../../support/constellation_profiles_from_public_records.dart';
import '../../support/disposable_pg_target.dart';

/// The constellation FULL read freezes the visibility memo: while another
/// connection keeps committing trust changes, its frozen snapshot computes the
/// visible set at most once per (viewer, context), with the tx-local freeze
/// flag already set. The anchor apply no longer consults visibility at all
/// (a pin beats visibility), so it neither computes it nor fails on an outage.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_FROZEN_VISIBILITY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_cfrozen',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Ucfrozenview01';
  const peer = 'Ucfrozenpeer01';
  const churnA = 'Ucfrozenchna01';
  const churnB = 'Ucfrozenchnb01';
  const ctx = '';
  const attempts = 5;

  late DisposablePgWriterSession session;
  late Connection writer;
  late Connection churn;
  late TenturaDb db;
  late ConstellationFieldRepository fieldRepository;
  late ConstellationAnchorRepository anchorRepository;

  Future<void> trust(Connection on, String s, String o, int amount) =>
      on.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$s', '$o', $amount, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount, updated_at = now()
''');

  // Sequences cannot count calls made inside the FULL read's read-only
  // transaction, so the wrapper below takes a session-level advisory lock with
  // a random sub-key per call (classid 7001 = every call, 7002 = calls made
  // with the freeze flag set); locks survive rollback and are counted here.
  Future<int> locksHeld(int classId) async {
    final rows = await writer.execute(
      "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' "
      'AND classid = $classId AND database = '
      '(SELECT oid FROM pg_database WHERE datname = current_database())',
    );
    return rows.single.single! as int;
  }

  var callsBefore = 0;
  var flagCallsBefore = 0;

  Future<void> resetCounters() async {
    // The stored visible set (m0235) would answer without computing.
    await writer.execute('DELETE FROM public.person_visible_set_cache');
    callsBefore = await locksHeld(7001);
    flagCallsBefore = await locksHeld(7002);
  }

  Future<int> calls() async => await locksHeld(7001) - callsBefore;
  Future<int> flagCalls() async => await locksHeld(7002) - flagCallsBefore;

  /// Runs [attempt] [attempts] times while a second connection commits trust
  /// changes without pause; each attempt must compute exactly once, with the
  /// freeze flag set at that first computation.
  ///
  /// [storesFirst] is for the FULL read, which stores the set in its own
  /// transaction before the frozen snapshot; [noComputation] is for the apply,
  /// which must not compute the set.
  Future<void> expectOneFrozenComputationPerAttempt(
    Future<void> Function() attempt, {
    bool flagSetAtComputation = true,
    bool storesFirst = false,
    bool noComputation = false,
  }) async {
    var stop = false;
    final churner = () async {
      var i = 0;
      while (!stop) {
        await trust(churn, churnA, churnB, (i++).isEven ? -1 : 1);
      }
    }();
    try {
      for (var i = 0; i < attempts; i++) {
        await resetCounters();
        await attempt();
        final flagged = await flagCalls();
        if (noComputation) {
          expect(await calls(), 0, reason: 'attempt $i');
        } else if (storesFirst) {
          // The read-only snapshot cannot fill the stored visible set, so the
          // read stores it first (unflagged, own transaction); churn may
          // invalidate it, and then the frozen snapshot computes once more.
          expect(flagged, lessThanOrEqualTo(1), reason: 'attempt $i');
          expect(await calls(), inInclusiveRange(1, 2), reason: 'attempt $i');
        } else {
          expect(await calls(), 1, reason: 'attempt $i');
          if (flagSetAtComputation) {
            expect(flagged, 1, reason: 'attempt $i');
          }
        }
      }
    } finally {
      stop = true;
      await churner;
    }
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    churn = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    db = openDisposablePgDatabase(target);
    final profiles = _PgProfileLookup(db);
    fieldRepository = ConstellationFieldRepository(db, profiles);
    anchorRepository = constellationAnchorRepositoryFor(db);

    for (final id in [viewer, peer, churnA, churnB]) {
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');
    }
    await trust(writer, viewer, peer, 1);
    await trust(writer, peer, viewer, 1);

    await writer.execute('CREATE TABLE public._cfrozen_mr_down (down bool)');
    await writer.execute('''
ALTER FUNCTION public.person_visible_peers_symmetric(text, text)
  RENAME TO _cfrozen_symmetric_impl
''');
    await writer.execute(r'''
CREATE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text)
RETURNS TABLE(peer_id text) LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_advisory_lock(7001, (random() * 1000000000)::int);
  -- widen the window so the churning connection commits mid-attempt
  PERFORM pg_sleep(0.05);
  IF EXISTS (SELECT 1 FROM public._cfrozen_mr_down) THEN
    RAISE EXCEPTION 'simulated MeritRank outage';
  END IF;
  IF current_setting('tentura_visibility.frozen', true) = 'on' THEN
    PERFORM pg_advisory_lock(7002, (random() * 1000000000)::int);
  END IF;
  RETURN QUERY SELECT s.peer_id FROM public._cfrozen_symmetric_impl(viewer_id, ctx) s;
END;
$$
''');
  });

  tearDownAll(() async {
    await churn.close();
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  test(
    'a FULL constellation read under continuous trust churn computes the '
    'visible set once, with the freeze flag set',
    () => expectOneFrozenComputationPerAttempt(() async {
      final snapshot = await fieldRepository.readSnapshot(
        viewerId: viewer,
        context: ctx,
        params: (
          filters: ConstellationFieldMembershipFilters.defaults,
          projection: ConstellationProjection.full,
        ),
      );
      expect(snapshot.peers.map((p) => p.id), contains(peer));
    }, storesFirst: true),
  );

  test(
    'an anchor apply under continuous trust churn does not compute the '
    'visible set',
    () => expectOneFrozenComputationPerAttempt(() async {
      final result = await anchorRepository.applyAnchorUpsert(
        viewerId: viewer,
        context: ctx,
        target: ConstellationAnchorTarget.person(peer),
        position: const ConstellationAnchorPosition(
          xUnits: 1,
          yUnits: 1,
          coordinateSpaceVersion: 1,
        ),
      );
      expect(result, isNotNull);
    }, noComputation: true),
  );

  group('when MeritRank fails', () {
    setUp(() async {
      await writer.execute('DELETE FROM public.person_visible_set_cache');
      await writer.execute('INSERT INTO public._cfrozen_mr_down VALUES (true)');
    });
    tearDown(() => writer.execute('DELETE FROM public._cfrozen_mr_down'));

    test(
      'a FULL constellation read fails closed to an empty peer set',
      () async {
        final snapshot = await fieldRepository.readSnapshot(
          viewerId: viewer,
          context: ctx,
          params: (
            filters: ConstellationFieldMembershipFilters.defaults,
            projection: ConstellationProjection.full,
          ),
        );
        // A pin of an earlier test stays on the map, but as an invisible
        // peer: nobody else is on it.
        final pinned = snapshot.anchorProjection.pinnedPeers;
        expect(pinned.where((p) => p.visible), isEmpty);
        expect(
          snapshot.peers.map((p) => p.id).toSet().difference({
            for (final p in pinned) p.id,
          }),
          isEmpty,
        );
      },
    );

    test(
      'an anchor apply does not depend on MeritRank and still pins the person',
      () async {
        final result = await anchorRepository.applyAnchorUpsert(
          viewerId: viewer,
          context: ctx,
          target: ConstellationAnchorTarget.person(peer),
          position: const ConstellationAnchorPosition(
            xUnits: 1,
            yUnits: 1,
            coordinateSpaceVersion: 1,
          ),
        );
        expect(result.anchor.target, ConstellationAnchorTarget.person(peer));
      },
    );
  });
}

/// Avoids GetIt-backed presence mapping in pg tests.
final class _PgProfileLookup implements UserProfileBatchLookup {
  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) => constellationProfilesFromRecords(this, ids);

  _PgProfileLookup(this._database);

  final TenturaDb _database;

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async {
    final idList = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (idList.isEmpty) {
      return {};
    }
    final users = await _database.managers.users
        .filter((u) => u.id.isIn(idList))
        .get();
    return {
      for (final user in users)
        user.id: UserEntity(id: user.id, displayName: user.displayName),
    };
  }

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async {
    final entities = await userEntitiesByIds(ids);
    return {
      for (final entry in entities.entries)
        entry.key: UserPublicRecord(
          id: entry.value.id,
          displayName: entry.value.displayName,
          description: entry.value.description,
          isMutualFriend: reciprocalPeerIds.contains(entry.key),
          subjectExplicitlyTrustsViewer: trustsViewerPeerIds.contains(
            entry.key,
          ),
          userAvailability: null,
        ),
    };
  }
}
