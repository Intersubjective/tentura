@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../../support/constellation_anchor_batch_fixture.dart';
import '../../support/constellation_profiles_from_public_records.dart';
import '../../support/disposable_pg_target.dart';

/// A FULL read asks `constellation_trust_edges` only for the graph's nodes
/// (the capped graph peers and the viewer), not for every visible peer, unless
/// the anchor projection already loaded the full set for its support closure;
/// then it reuses that set. Either way the edges are the full set's edges
/// among the graph's nodes.
///
/// Visibility is stubbed (`person_visible_peers_symmetric` returns a fixed
/// list) so the viewer can see more peers than [kConstellationPeerCap].
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_FULL_TRUST_EDGES_SCOPE_TEST_DB',
    defaultNamePrefix: 'tentura_test_cfte',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Ucftescopeview1';
  const ctx = '';
  const visibleCount = kConstellationPeerCap + 60;
  final peers = [
    for (var i = 0; i < visibleCount; i++)
      'Ucftepeer${i.toString().padLeft(5, '0')}',
  ];

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late _TrustEdgeCallRecorder recorder;
  late ConstellationFieldRepository fieldRepository;
  late ConstellationAnchorRepository anchorRepository;

  Future<ConstellationFieldSnapshot> readFull() => fieldRepository.readSnapshot(
    viewerId: viewer,
    context: ctx,
    params: (
      filters: ConstellationFieldMembershipFilters.defaults,
      projection: ConstellationProjection.full,
    ),
  );

  Set<(String, String, int)> edgeSet(Iterable<ConstellationEdgeRecord> edges) =>
      {for (final e in edges) (e.src, e.dst, e.tier)};

  /// The full set's edges among the viewer and the snapshot's graph peers
  /// (its peers minus the pinned and support peers the anchors reserve).
  Future<Set<(String, String, int)>> expectedEdges(
    ConstellationFieldSnapshot snapshot,
  ) async {
    final reserved = {
      for (final p in snapshot.anchorProjection.pinnedPeers) p.id,
      for (final p in snapshot.anchorProjection.supportPeers) p.id,
    };
    final nodes = {
      viewer,
      for (final p in snapshot.peers)
        if (!reserved.contains(p.id)) p.id,
    };
    final all = await db.withConnectionScope(
      () => fieldRepository.trustEdges(
        viewerId: viewer,
        context: ctx,
        nodeIds: {viewer, ...peers},
      ),
    );
    return edgeSet(
      all.where((e) => nodes.contains(e.src) && nodes.contains(e.dst)),
    );
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    recorder = _TrustEdgeCallRecorder();
    db = TenturaDb(target.databaseEnv, scopeInterceptor: () => recorder);
    fieldRepository = ConstellationFieldRepository(db, _PgProfileLookup(db));
    anchorRepository = constellationAnchorRepositoryFor(db);

    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
SELECT id, id, 'pk-' || id, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
FROM unnest(ARRAY[${[viewer, ...peers].map((id) => "'$id'").join(',')}]) AS id
ON CONFLICT (id) DO NOTHING
''');
    // A ring with chords: edges inside the capped graph, across its border
    // and wholly outside it.
    final votes = <String>[];
    for (var i = 0; i < visibleCount; i++) {
      votes
        ..add("('${peers[i]}', '${peers[(i + 1) % visibleCount]}')")
        ..add("('${peers[i]}', '${peers[(i + 37) % visibleCount]}')");
    }
    votes
      ..add("('$viewer', '${peers.first}')")
      ..add("('${peers.last}', '$viewer')");
    await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
SELECT v.s, v.o, 1, now(), now()
FROM (VALUES ${votes.join(',')}) AS v(s, o)
ON CONFLICT (subject, object) DO NOTHING
''');

    await writer.execute(
      'CREATE TABLE public._cfte_visible (peer_id text PRIMARY KEY)',
    );
    await writer.execute('''
INSERT INTO public._cfte_visible
SELECT unnest(ARRAY[${peers.map((id) => "'$id'").join(',')}])
''');
    await writer.execute('''
ALTER FUNCTION public.person_visible_peers_symmetric(text, text)
  RENAME TO _cfte_symmetric_impl
''');
    await writer.execute(r'''
CREATE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text)
RETURNS TABLE(peer_id text) LANGUAGE sql STABLE AS $$
  SELECT v.peer_id FROM public._cfte_visible v
$$
''');
  });

  setUp(() async {
    await writer.execute('DELETE FROM public.person_visible_set_cache');
    recorder.nodeCounts.clear();
  });

  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  test(
    'without anchors a FULL asks for trust edges among the graph nodes only',
    () async {
      final snapshot = await readFull();

      // The viewer trusts the first peer directly: it rides on top of the
      // cap (#246 Q6), which then takes the next peers in id order.
      expect(snapshot.peersCapped, isTrue);
      expect(snapshot.directContactIds, [peers.first]);
      expect(snapshot.peers, hasLength(kConstellationPeerCap + 1));
      expect(recorder.nodeCounts, [kConstellationPeerCap + 2]);
      expect(edgeSet(snapshot.edges), await expectedEdges(snapshot));
      expect(snapshot.edges, isNotEmpty);
    },
  );

  test(
    'with a pinned person the anchor projection loads the full set once and '
    'the FULL reuses it',
    () async {
      await anchorRepository.applyAnchorUpsert(
        viewerId: viewer,
        context: ctx,
        target: ConstellationAnchorTarget.person(peers.last),
        position: const ConstellationAnchorPosition(
          xUnits: 1,
          yUnits: 1,
          coordinateSpaceVersion: 1,
        ),
      );
      addTearDown(
        () => writer.execute(
          "DELETE FROM public.constellation_anchor WHERE viewer_id = '$viewer'",
        ),
      );
      recorder.nodeCounts.clear();

      final snapshot = await readFull();

      expect(recorder.nodeCounts, [visibleCount + 1]);
      expect(edgeSet(snapshot.edges), await expectedEdges(snapshot));
    },
  );
}

/// Records the node-array size of each `constellation_trust_edges` call made
/// in a leased connection scope.
final class _TrustEdgeCallRecorder extends QueryInterceptor {
  final nodeCounts = <int>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('constellation_trust_edges(')) {
      final nodes = args[2];
      nodeCounts.add(
        ((nodes is TypedValue ? nodes.value : nodes)! as List<Object?>).length,
      );
    }
    return super.runSelect(executor, statement, args);
  }
}

/// Avoids GetIt-backed presence mapping in pg tests.
final class _PgProfileLookup implements UserProfileBatchLookup {
  _PgProfileLookup(this._database);

  final TenturaDb _database;

  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) => constellationProfilesFromRecords(this, ids);

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
