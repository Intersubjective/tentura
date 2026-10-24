@Tags(['pg', 'mr'])
library;

import 'package:test/test.dart';

import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../../support/disposable_pg_target.dart';

/// One viewer with 450 Field candidates in groups. Group ids carry a letter so
/// that plain id order is the reverse of the priority order: far < near <
/// bond < direct < temporary < tagged.
final class _Scenario {
  _Scenario(
    this.key, {
    this.far = 0,
    this.near = 0,
    this.bond = 0,
    this.direct = 0,
    this.temporary = 0,
    this.tagged = 0,
  }) : assert(
         far + near + bond + direct + temporary + tagged == 450,
         'a scenario holds exactly 450 candidates',
       );

  final String key;
  final int far; // MR-visible, no trust edges: deepest BFS depth
  final int near; // MR-visible, trusted mutually by a direct contact
  final int bond; // outside the visible set, admitted to a shared Request
  final int direct; // mutual trust with the viewer
  final int temporary; // outside the visible set, forwarded a Request
  final int tagged; // MR-visible, tagged by the viewer

  String get viewer => 'Upf${key}viewer01';

  List<String> _ids(String group, int n) => [
    for (var i = 0; i < n; i++) 'Upf$key$group${i.toString().padLeft(4, '0')}',
  ];

  late final farIds = _ids('a', far);
  late final nearIds = _ids('b', near);
  late final bondIds = _ids('c', bond);
  late final directIds = _ids('d', direct);
  late final temporaryIds = _ids('e', temporary);
  late final taggedIds = _ids('f', tagged);

  List<String> get all => [
    ...farIds,
    ...nearIds,
    ...bondIds,
    ...directIds,
    ...temporaryIds,
    ...taggedIds,
  ];

  /// People that become visible through MeritRank edges.
  List<String> get mrVisible => [
    ...farIds,
    ...nearIds,
    ...directIds,
    ...taggedIds,
  ];
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_PEER_PRIORITY_MR_TEST_DB',
    defaultNamePrefix: 'tentura_test_peerprio',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const otherOwner = 'Upfotherown1';
  const otherTagId = 'Tpfother0001';

  // The cut falls inside the depth / id tier.
  final depthAndId = _Scenario(
    'A',
    far: 335,
    near: 60,
    bond: 10,
    direct: 30,
    temporary: 10,
    tagged: 5,
  );
  // The cut falls inside the bond / temporary tier; the depth tier is gone.
  final bondTemporary = _Scenario(
    'B',
    far: 10,
    near: 10,
    bond: 100,
    direct: 225,
    temporary: 100,
    tagged: 5,
  );
  // The cut falls inside the direct-contact tier; depth, bond and temporary
  // tiers are gone.
  final directContacts = _Scenario(
    'C',
    far: 20,
    near: 10,
    bond: 5,
    direct: 405,
    temporary: 5,
    tagged: 5,
  );
  // The cut falls inside the own-tagged tier; every other tier is gone.
  final ownTagged = _Scenario('D', far: 30, direct: 10, tagged: 410);
  final scenarios = [depthAndId, bondTemporary, directContacts, ownTagged];

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late ConstellationFieldRepository repository;

  String sqlArray(Iterable<String> ids) =>
      'ARRAY[${ids.map((id) => "'$id'").join(',')}]::text[]';

  String tagIdOf(_Scenario s) => 'Tpfprio${s.key}0001';

  Future<void> mrEdges(_Scenario s, {required bool put}) => db.customStatement(
    '''
SELECT ${put ? "mr_put_edge(e.src, e.dst, 0.75::double precision, ''::text, 0)" : 'mr_delete_edge(e.src, e.dst)'}
FROM (
  SELECT '${s.viewer}' AS src, id AS dst
  FROM unnest(${sqlArray(s.mrVisible)}) AS id
  UNION ALL
  SELECT id, '${s.viewer}' FROM unnest(${sqlArray(s.mrVisible)}) AS id
) e
''',
  );

  Future<void> setUpScenario(_Scenario s) async {
    await db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT id, 'name-' || id, 'pk-' || id
FROM unnest(${sqlArray([s.viewer, ...s.all])}) AS id
ON CONFLICT (id) DO NOTHING
''');
    await db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount)
SELECT '${s.viewer}', id, 1 FROM unnest(${sqlArray(s.directIds)}) AS id
UNION ALL
SELECT id, '${s.viewer}', 1 FROM unnest(${sqlArray(s.directIds)}) AS id
ON CONFLICT (subject, object) DO NOTHING
''');
    if (s.nearIds.isNotEmpty) {
      await db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount)
SELECT '${s.directIds.first}', id, 1 FROM unnest(${sqlArray(s.nearIds)}) AS id
UNION ALL
SELECT id, '${s.directIds.first}', 1 FROM unnest(${sqlArray(s.nearIds)}) AS id
ON CONFLICT (subject, object) DO NOTHING
''');
    }
    await mrEdges(s, put: true);
    if (s.bondIds.isNotEmpty) {
      await db.customStatement('''
INSERT INTO public.beacon (id, user_id, title, description, status,
  is_discoverable, published_at, created_at, updated_at, last_activity_at)
VALUES ('Bpf${s.key}bond0001', '${s.viewer}', 't', 'd', 0, true,
        now(), now(), now(), now())
''');
      await db.customStatement('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
SELECT 'Bpf${s.key}bond0001', id, 1, 3 FROM unnest(${sqlArray(s.bondIds)}) AS id
''');
    }
    if (s.temporaryIds.isNotEmpty) {
      await db.customStatement('''
INSERT INTO public.beacon (id, user_id, title, description, status,
  is_discoverable, published_at, created_at, updated_at, last_activity_at)
SELECT 'Bpftmp' || id, id, 't', 'd', 0, true, now(), now(), now(), now()
FROM unnest(${sqlArray(s.temporaryIds)}) AS id
''');
      await db.customStatement('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
SELECT 'Bpftmp' || id, id, '${s.viewer}'
FROM unnest(${sqlArray(s.temporaryIds)}) AS id
''');
    }
    await db.customStatement('''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES ('${tagIdOf(s)}', '${s.viewer}', 'prio', 'g', 0, 0)
''');
    await db.customStatement('''
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
SELECT '${tagIdOf(s)}', '${s.viewer}', id, 0
FROM unnest(${sqlArray(s.taggedIds)}) AS id
''');
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    db = openDisposablePgDatabase(target);
    repository = ConstellationFieldRepository(db, _PgProfileLookup(db));

    await db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$otherOwner', 'other', 'pk-other')
ON CONFLICT (id) DO NOTHING
''');
    for (final s in scenarios) {
      await setUpScenario(s);
    }
    // Another owner tags one tagged person, the highest-id far peer (which
    // is cut) and the lowest-id far peer (which is kept): none of it may
    // count for priority or appear as an own tag.
    final farSorted = depthAndId.farIds.toList()..sort();
    await db.customStatement('''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES ('$otherTagId', '$otherOwner', 'other', 'g', 0, 0)
''');
    await db.customStatement('''
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
SELECT '$otherTagId', '$otherOwner', id, 0 FROM unnest(${sqlArray([
      depthAndId.taggedIds.last,
      farSorted.last,
      farSorted.first,
    ])}) AS id
''');
  });

  tearDownAll(() async {
    for (final s in scenarios) {
      await mrEdges(s, put: false);
    }
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  Future<Set<String>> keptPeers(_Scenario s) async {
    // MeritRank's graph is shared with every suite in the run: put this
    // scenario's edges again (idempotent) so a reset elsewhere cannot leave
    // the read with an empty visible set.
    await mrEdges(s, put: true);
    final snapshot = await repository.readSnapshot(
      viewerId: s.viewer,
      context: '',
      params: (
        filters: ConstellationFieldMembershipFilters.defaults,
        projection: ConstellationProjection.full,
      ),
    );
    expect(snapshot.peersCapped, isTrue);
    final kept = snapshot.peers.map((p) => p.id).toSet();
    expect(kept.intersection(s.all.toSet()), hasLength(400));
    return kept;
  }

  int keptCount(Set<String> kept, List<String> group) =>
      group.where(kept.contains).length;

  test('the Field peer cap is 400', () {
    expect(kConstellationPeerCap, 400);
  });

  group('cut inside the depth and id tier', () {
    final s = depthAndId;

    test(
      'keeps every higher tier and drops the 50 last by depth then id',
      () async {
        final kept = await keptPeers(s);

        expect(kept.containsAll(s.taggedIds), isTrue, reason: 'own-tagged');
        expect(kept.containsAll(s.directIds), isTrue, reason: 'direct');
        expect(kept.containsAll(s.bondIds), isTrue, reason: 'bond');
        expect(kept.containsAll(s.temporaryIds), isTrue, reason: 'temporary');

        // The depth tier orders by BFS depth over the trust edges MeritRank
        // reports, which also link far peers through the viewer hub and so
        // depend on the shared graph: derive the depths from those same edges
        // instead of assuming the far peers have none.
        final edges = await db.withConnectionScope(
          () => repository.trustEdges(
            viewerId: s.viewer,
            context: '',
            nodeIds: {s.viewer, ...s.mrVisible},
          ),
        );
        final adjacency = <String, List<String>>{};
        for (final e in edges) {
          (adjacency[e.src] ??= []).add(e.dst);
          (adjacency[e.dst] ??= []).add(e.src);
        }
        final depth = <String, int>{s.viewer: 0};
        final queue = [s.viewer];
        for (var i = 0; i < queue.length; i++) {
          for (final next in adjacency[queue[i]] ?? const <String>[]) {
            if (!depth.containsKey(next)) {
              depth[next] = depth[queue[i]]! + 1;
              queue.add(next);
            }
          }
        }
        final ranked = [...s.nearIds, ...s.farIds]
          ..sort((a, b) {
            final byDepth = (depth[a] ?? 1 << 30).compareTo(
              depth[b] ?? 1 << 30,
            );
            return byDepth != 0 ? byDepth : a.compareTo(b);
          });

        expect(
          s.all.toSet().difference(kept),
          ranked.sublist(ranked.length - 50).toSet(),
        );
      },
    );

    test('another owner tag on a person never counts for priority and never '
        'appears in own tag ids at the cap', () async {
      await mrEdges(s, put: true);
      final snapshot = await repository.readSnapshot(
        viewerId: s.viewer,
        context: '',
        params: (
          filters: ConstellationFieldMembershipFilters.defaults,
          projection: ConstellationProjection.full,
        ),
      );
      final byId = {for (final p in snapshot.peers) p.id: p};
      final farSorted = s.farIds.toList()..sort();

      expect(byId.keys, isNot(contains(farSorted.last)));
      for (final id in s.taggedIds) {
        expect(byId[id]!.ownTagIds, [tagIdOf(s)], reason: id);
      }
      expect(byId[farSorted.first]!.ownTagIds, isEmpty);
      expect(
        byId.values
            .where((p) => !s.taggedIds.contains(p.id))
            .every((p) => p.ownTagIds.isEmpty),
        isTrue,
      );
    });
  });

  test(
    'cut inside the bond and temporary tier: own-tagged and direct '
    'peers stay, the depth tier goes, 30 bond or temporary peers go',
    () async {
      final s = bondTemporary;
      final kept = await keptPeers(s);

      expect(kept.containsAll(s.taggedIds), isTrue);
      expect(kept.containsAll(s.directIds), isTrue);
      expect(keptCount(kept, [...s.farIds, ...s.nearIds]), 0);
      expect(keptCount(kept, [...s.bondIds, ...s.temporaryIds]), 170);
    },
  );

  test('cut inside the direct-contact tier: own-tagged peers stay, the '
      'bond, temporary and depth tiers go, 10 direct contacts go', () async {
    final s = directContacts;
    final kept = await keptPeers(s);

    expect(kept.containsAll(s.taggedIds), isTrue);
    expect(
      keptCount(kept, [
        ...s.farIds,
        ...s.nearIds,
        ...s.bondIds,
        ...s.temporaryIds,
      ]),
      0,
    );
    expect(keptCount(kept, s.directIds), 395);
  });

  test('cut inside the own-tagged tier: only 400 tagged people stay and '
      'every direct and deeper peer goes', () async {
    final s = ownTagged;
    final kept = await keptPeers(s);

    expect(keptCount(kept, s.taggedIds), 400);
    expect(keptCount(kept, [...s.directIds, ...s.farIds]), 0);
  });
}

/// Avoids GetIt-backed presence mapping in pg tests.
final class _PgProfileLookup implements UserProfileBatchLookup {
  _PgProfileLookup(this._database);

  final TenturaDb _database;

  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
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
        user.id: ConstellationPeerRecord(
          id: user.id,
          displayName: user.displayName,
        ),
    };
  }

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async => const {};

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async => const {};
}
