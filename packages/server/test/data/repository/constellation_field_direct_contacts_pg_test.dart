@Tags(['pg'])
library;

import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
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
import '../../support/disposable_pg_target.dart';

/// #246 population contract: everyone the viewer trusts directly is on the
/// field, uncapped (Q6). A one-way contact outside the visible set is a
/// contact node without content (Q5): identity only and the viewer's own edge.
/// A block in either direction removes the person altogether.
///
/// Without MeritRank edges a peer is visible exactly when trust is mutual and
/// explicit, so one-way trust here always fails the visibility wall.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_DIRECT_CONTACTS_TEST_DB',
    defaultNamePrefix: 'tentura_test_dircontact',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Udcviewer001';
  const ctx = '';

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late ConstellationFieldRepository fieldRepository;
  late ConstellationAnchorRepository anchorRepository;

  Future<void> insertUser(String id, {String? handle}) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, handle, public_key, created_at, updated_at)
VALUES ('$id', 'name-$id', ${handle == null ? 'NULL' : "'$handle'"}, 'pk-$id',
        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<void> trust(String subject, String object) => db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

  Future<void> mutualTrust(String a, String b) async {
    await trust(a, b);
    await trust(b, a);
  }

  Future<void> block(String blocker, String blocked) => db.customStatement('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blocker', '$blocked', '$blocker')
ON CONFLICT DO NOTHING
''');

  Future<void> insertBeacon(String id, String authorId) =>
      db.customStatement('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at, last_activity_at
) VALUES (
  '$id', '$authorId', 'title-$id', 'desc', 0, true,
  now(), now(), now(), now()
)
ON CONFLICT (id) DO NOTHING
''');

  Future<ConstellationFieldSnapshot> read({
    ConstellationProjection projection = ConstellationProjection.full,
  }) => fieldRepository.readSnapshot(
    viewerId: viewer,
    context: ctx,
    params: (
      filters: ConstellationFieldMembershipFilters.defaults,
      projection: projection,
    ),
  );

  Iterable<ConstellationEdgeRecord> edgesOf(
    ConstellationFieldSnapshot snapshot,
    String id,
  ) => snapshot.edges.where((e) => e.src == id || e.dst == id);

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    db = openDisposablePgDatabase(target);
    fieldRepository = ConstellationFieldRepository(db, _PgProfileLookup(db));
    anchorRepository = constellationAnchorRepositoryFor(db);
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  setUp(() async {
    await db.customStatement('DELETE FROM public.constellation_anchor');
    await db.customStatement('DELETE FROM public.constellation_anchor_cursor');
    await db.customStatement('DELETE FROM public.beacon_participant');
    await db.customStatement('DELETE FROM public.beacon');
    await db.customStatement('DELETE FROM public.user_block');
    await db.customStatement('DELETE FROM public.vote_user');
    await db.customStatement('DELETE FROM public."user"');
    await insertUser(viewer);
  });

  group('one-way trust', () {
    const oneWay = 'Udconeway001';
    const friendOfOneWay = 'Udcfof000001';

    setUp(() async {
      await insertUser(oneWay, handle: 'oneway');
      await insertUser(friendOfOneWay);
      await trust(viewer, oneWay);
      await mutualTrust(oneWay, friendOfOneWay);
      await insertBeacon('Bdconewayreq1', oneWay);
    });

    test('is a contact node with identity only', () async {
      final snapshot = await read();

      expect(snapshot.directContactIds, [oneWay]);
      final node = snapshot.peers.singleWhere((p) => p.id == oneWay);
      expect(node.contactOnly, isTrue);
      expect(node.visible, isFalse);
      expect(node.displayName, 'name-$oneWay');
      expect(node.handle, isNull);
    });

    test(
      'carries only the viewer own edge and none of their content',
      () async {
        final snapshot = await read();

        expect(edgesOf(snapshot, oneWay), [
          const ConstellationEdgeRecord(src: viewer, dst: oneWay, tier: 1),
        ]);
        expect(
          snapshot.peers.map((p) => p.id),
          isNot(contains(friendOfOneWay)),
        );
        expect(
          snapshot.requests.map((r) => r.authorId),
          isNot(contains(oneWay)),
        );
        expect(snapshot.posts.map((p) => p.authorId), isNot(contains(oneWay)));
      },
    );

    test('maps to the wire with the contact flag and no handle', () async {
      final wire = constellationFieldToGqlMap(await read());

      expect(wire['directContactIds'], [oneWay]);
      final peer = (wire['peers']! as List<Object?>)
          .cast<Map<String, dynamic>>()
          .singleWhere((p) => p['id'] == oneWay);
      expect(peer['contactOnly'], isTrue);
      expect(peer['visible'], isFalse);
      expect(peer['handle'], isNull);
    });

    test('a pinned contact node stays a contact node', () async {
      await anchorRepository.applyAnchorUpsert(
        viewerId: viewer,
        context: ctx,
        target: ConstellationAnchorTarget.person(oneWay),
        position: const ConstellationAnchorPosition(
          xUnits: 2,
          yUnits: 2,
          coordinateSpaceVersion: 1,
        ),
      );

      final snapshot = await read();

      final pinned = snapshot.anchorProjection.pinnedPeers.single;
      expect(pinned.visible, isFalse);
      expect(pinned.contactOnly, isTrue);
      expect(pinned.handle, isNull, reason: 'identity only in every copy');
      final anchorsOnly = await read(
        projection: ConstellationProjection.anchors,
      );
      expect(anchorsOnly.anchorProjection.pinnedPeers.single.handle, isNull);
      expect(
        snapshot.peers.singleWhere((p) => p.id == oneWay).contactOnly,
        isTrue,
      );
      expect(edgesOf(snapshot, oneWay), hasLength(1));
    });

    test('trust the other way only puts nobody on the field', () async {
      await db.customStatement('DELETE FROM public.vote_user');
      await trust(oneWay, viewer);

      final snapshot = await read();

      expect(snapshot.directContactIds, isEmpty);
      expect(snapshot.peers, isEmpty);
    });
  });

  group('mutual trust', () {
    const mutual = 'Udcmutual001';

    setUp(() async {
      await insertUser(mutual, handle: 'mutual');
      await mutualTrust(viewer, mutual);
      await insertBeacon('Bdcmutualreq1', mutual);
    });

    test('is an ordinary peer with content and both edges', () async {
      final snapshot = await read();

      expect(snapshot.directContactIds, [mutual]);
      final node = snapshot.peers.singleWhere((p) => p.id == mutual);
      expect(node.contactOnly, isFalse);
      expect(node.visible, isTrue);
      expect(node.handle, 'mutual');
      expect(
        snapshot.requests.map((r) => r.id),
        contains('Bdcmutualreq1'),
      );
      expect(edgesOf(snapshot, mutual).toSet(), {
        const ConstellationEdgeRecord(src: viewer, dst: mutual, tier: 1),
        const ConstellationEdgeRecord(src: mutual, dst: viewer, tier: 1),
      });
    });

    test('an ANCHORS read lists no direct contacts', () async {
      final snapshot = await read(projection: ConstellationProjection.anchors);

      expect(snapshot.directContactIds, isEmpty);
      expect(snapshot.peers, isEmpty);
    });
  });

  group('a block in either direction removes the contact', () {
    const mutual = 'Udcblockmut1';
    const oneWay = 'Udcblockone1';

    setUp(() async {
      await insertUser(mutual);
      await insertUser(oneWay);
      await mutualTrust(viewer, mutual);
      await trust(viewer, oneWay);
    });

    for (final viewerBlocks in [true, false]) {
      final who = viewerBlocks ? 'the viewer blocks' : 'the contact blocks';
      test('$who: mutual and one-way contacts are absent', () async {
        for (final other in [mutual, oneWay]) {
          viewerBlocks
              ? await block(viewer, other)
              : await block(other, viewer);
        }

        final snapshot = await read();

        expect(snapshot.directContactIds, isEmpty);
        expect(snapshot.peers, isEmpty);
        expect(snapshot.edges, isEmpty);
      });
    }
  });

  group('contact nodes are not capped', () {
    test('mutual contacts within the peer cap plus one-way contacts beyond it '
        'are all present and the snapshot is not capped', () async {
      const mutualCount = kConstellationPeerCap - 30;
      const oneWayCount = 130;
      final mutual = [
        for (var i = 0; i < mutualCount; i++)
          'Udcmut${i.toString().padLeft(4, '0')}',
      ];
      final oneWay = [
        for (var i = 0; i < oneWayCount; i++)
          'Udcone${i.toString().padLeft(4, '0')}',
      ];
      await db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT id, 'name-' || id, 'pk-' || id
FROM unnest(ARRAY[${[...mutual, ...oneWay].map((id) => "'$id'").join(',')}]) AS id
''');
      await db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount)
SELECT '$viewer', id, 1 FROM unnest(ARRAY[${[...mutual, ...oneWay].map((id) => "'$id'").join(',')}]) AS id
UNION ALL
SELECT id, '$viewer', 1 FROM unnest(ARRAY[${mutual.map((id) => "'$id'").join(',')}]) AS id
''');

      final snapshot = await read();

      expect(snapshot.peersCapped, isFalse);
      expect(snapshot.directContactIds, [...mutual, ...oneWay]..sort());
      final byId = {for (final p in snapshot.peers) p.id: p};
      expect(byId.keys.toSet(), {...mutual, ...oneWay});
      expect(mutual.every((id) => !byId[id]!.contactOnly), isTrue);
      expect(oneWay.every((id) => byId[id]!.contactOnly), isTrue);
      for (final id in oneWay) {
        expect(edgesOf(snapshot, id), hasLength(1), reason: id);
      }
    });
  });

  test(
    'a pinned Request support path survives beside direct contacts',
    () async {
      const bridge = 'Udcbridge001';
      const author = 'Udcauthor001';
      const contact = 'Udccontact01';
      for (final id in [bridge, author, contact]) {
        await insertUser(id);
      }
      await mutualTrust(viewer, bridge);
      await mutualTrust(viewer, contact);
      await insertBeacon('Bdcpinned001', author);
      await db.customStatement('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('Bdcpinned001', '$viewer', 6, 3)
ON CONFLICT DO NOTHING
''');
      await anchorRepository.applyAnchorUpsert(
        viewerId: viewer,
        context: ctx,
        target: ConstellationAnchorTarget.beacon('Bdcpinned001'),
        position: const ConstellationAnchorPosition(
          xUnits: 1,
          yUnits: 1,
          coordinateSpaceVersion: 1,
        ),
      );

      final snapshot = await read();

      expect(
        snapshot.anchorProjection.pinnedRequests.map((r) => r.id),
        ['Bdcpinned001'],
      );
      expect(snapshot.directContactIds, [bridge, contact]..sort());
      expect(
        snapshot.peers.map((p) => p.id),
        containsAll([bridge, contact, author]),
      );
    },
  );
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
          handle: user.handle,
        ),
    };
  }

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
  }) async => const {};
}
