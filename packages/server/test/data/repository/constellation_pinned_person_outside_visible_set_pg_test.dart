@Tags(['pg', 'mr'])
library;

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

/// A pinned person who lost visibility stays in the anchor projection (with
/// `visible: false`). Binding architecture rev 10 D15 / section 5.10 keeps a
/// viewer-blocked pin marked, hides a person who blocked the viewer, and keeps
/// unreadable pinned Requests as content-free placeholders. Unpin removes them.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_PINNED_OUTSIDE_VISIBLE_TEST_DB',
    defaultNamePrefix: 'tentura_test_pinvis',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Upinvisview01';
  const visiblePeer = 'Upinvisvisb01';
  const stranger = 'Upinvisstrg01';
  const ctx = '';

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late ConstellationFieldRepository fieldRepository;
  late ConstellationAnchorRepository anchorRepository;

  Future<void> insertUser(String id) => db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

  Future<void> reciprocalTrust(String a, String b) => db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$a', '$b', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$b', '$a', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

  Future<void> insertBeacon(String id, String authorId) =>
      db.customStatement('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$id', '$authorId', 'title-$id', 'desc', 0, true,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
''');

  Future<void> block(String blocker, String blocked) => db.customStatement('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blocker', '$blocked', '$blocker')
''');

  Future<void> unblock(String blocker, String blocked) => db.customStatement('''
DELETE FROM public.user_block
WHERE blocker_id = '$blocker' AND blocked_id = '$blocked'
''');

  Future<void> pinStranger() => anchorRepository.applyAnchorUpsert(
    viewerId: viewer,
    context: ctx,
    target: ConstellationAnchorTarget.person(stranger),
    position: const ConstellationAnchorPosition(
      xUnits: 3,
      yUnits: -2,
      coordinateSpaceVersion: 1,
    ),
  );

  Future<void> pinBeacon(String id) => anchorRepository.applyAnchorUpsert(
    viewerId: viewer,
    context: ctx,
    target: ConstellationAnchorTarget.beacon(id),
    position: const ConstellationAnchorPosition(
      xUnits: 1,
      yUnits: 1,
      coordinateSpaceVersion: 1,
    ),
  );

  Future<ConstellationFieldSnapshot> read(ConstellationProjection projection) =>
      fieldRepository.readSnapshot(
        viewerId: viewer,
        context: ctx,
        params: (
          filters: ConstellationFieldMembershipFilters.defaults,
          projection: projection,
        ),
      );

  final projections = [
    ConstellationProjection.anchors,
    ConstellationProjection.full,
  ];

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
    await db.customStatement('DELETE FROM public.beacon');
    await db.customStatement('DELETE FROM public.user_block');
    await db.customStatement('DELETE FROM public.vote_user');
    await db.customStatement('DELETE FROM public."user"');
    for (final id in [viewer, visiblePeer, stranger]) {
      await insertUser(id);
    }
    await reciprocalTrust(viewer, visiblePeer);
  });

  for (final projection in projections) {
    group(
      'pinned person outside the visible set in a ${projection.wireValue} read',
      () {
        test('is returned with visible false and a resolved profile', () async {
          await pinStranger();

          final read0 = (await read(projection)).anchorProjection;
          final peers = read0.pinnedPeers;

          expect(peers.map((p) => p.id), [stranger]);
          expect(peers.single.visible, isFalse);
          expect(peers.single.displayName, stranger);
          expect(read0.anchors.map((a) => a.target.id), [stranger]);
        });

        test('keeps visible true for a visible pinned person', () async {
          await anchorRepository.applyAnchorUpsert(
            viewerId: viewer,
            context: ctx,
            target: ConstellationAnchorTarget.person(visiblePeer),
            position: const ConstellationAnchorPosition(
              xUnits: 1,
              yUnits: 1,
              coordinateSpaceVersion: 1,
            ),
          );

          final peers = (await read(projection)).anchorProjection.pinnedPeers;

          expect(peers.single.visible, isTrue);
        });

        test(
          'disappears when blocked by the other side and returns on unblock',
          () async {
            await pinStranger();
            await block(stranger, viewer);
            final blocked = (await read(projection)).anchorProjection;
            expect(blocked.pinnedPeers, isEmpty);
            expect(blocked.anchors, isEmpty);

            await unblock(stranger, viewer);
            final restored = (await read(projection)).anchorProjection;
            expect(restored.pinnedPeers.map((p) => p.id), [stranger]);
            expect(restored.pinnedPeers.single.visible, isFalse);
            expect(restored.pinnedPeers.single.displayName, stranger);
            expect(restored.anchors.map((a) => a.target.id), [stranger]);
          },
        );

        test(
          'stays marked when blocked by the viewer and clears the mark on unblock',
          () async {
            await pinStranger();
            await block(viewer, stranger);
            final blocked = (await read(projection)).anchorProjection;
            expect(blocked.pinnedPeers.map((p) => p.id), [stranger]);
            expect(blocked.pinnedPeers.single.pinState, 'blockedByMe');
            expect(blocked.pinnedPeers.single.displayName, stranger);
            expect(blocked.pinnedPeers.single.visible, isFalse);
            expect(blocked.anchors.map((a) => a.target.id), [stranger]);
            final position = blocked.anchors.single.position;

            await unblock(viewer, stranger);
            final restored = (await read(projection)).anchorProjection;
            expect(restored.pinnedPeers.map((p) => p.id), [stranger]);
            expect(restored.pinnedPeers.single.visible, isFalse);
            expect(restored.pinnedPeers.single.displayName, stranger);
            expect(restored.pinnedPeers.single.pinState, isNull);
            expect(restored.anchors.map((a) => a.target.id), [stranger]);
            expect(restored.anchors.single.position, position);
          },
        );

        test('is removed by unpinning', () async {
          await pinStranger();
          await anchorRepository.applyAnchorDelete(
            viewerId: viewer,
            target: ConstellationAnchorTarget.person(stranger),
          );

          final projectionRead = (await read(projection)).anchorProjection;

          expect(projectionRead.anchors, isEmpty);
          expect(projectionRead.pinnedPeers, isEmpty);
        });

        test('has no trust edge in the support edges', () async {
          await reciprocalTrust(stranger, visiblePeer);
          await pinStranger();

          final edges = (await read(projection)).anchorProjection.supportEdges;

          expect(
            edges.where((e) => e.src == stranger || e.dst == stranger),
            isEmpty,
          );
        });
      },
    );
  }

  test(
    'Requests of a pinned non-visible person are not added to the field, '
    'while a visible person Request is',
    () async {
      await insertBeacon('Bpinvisreq01', stranger);
      await insertBeacon('Bpinvisreq02', visiblePeer);
      await pinStranger();

      final snapshot = await read(ConstellationProjection.full);

      expect(snapshot.anchorProjection.pinnedPeers.map((p) => p.id), [
        stranger,
      ]);
      final ids = snapshot.requests.map((r) => r.id);
      expect(ids, contains('Bpinvisreq02'));
      expect(ids, isNot(contains('Bpinvisreq01')));
    },
  );

  group('pinned Request read wall', () {
    test(
      'an unreadable pinned Request stays as a placeholder beside a readable pin',
      () async {
        // Closed (status 5), not discoverable, no relation to the viewer:
        // beacon_can_read_content is false for it. The viewer's own Request is
        // always readable.
        await db.customStatement('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  'Bpinvishid01', '$stranger', 't', 'd', 5, false,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
''');
        await insertBeacon('Bpinvisown01', viewer);
        await pinBeacon('Bpinvishid01');
        await pinBeacon('Bpinvisown01');

        final projectionRead = (await read(
          ConstellationProjection.anchors,
        )).anchorProjection;

        expect(
          projectionRead.pinnedRequests.map((r) => r.id),
          unorderedEquals(['Bpinvishid01', 'Bpinvisown01']),
        );
        expect(
          projectionRead.anchors.map((a) => a.target.id),
          unorderedEquals(['Bpinvishid01', 'Bpinvisown01']),
        );
        final placeholder = projectionRead.pinnedRequests.singleWhere(
          (r) => r.id == 'Bpinvishid01',
        );
        expect(placeholder.pinState, 'noAccess');
        expect(placeholder.title, isEmpty);
        expect(placeholder.authorId, isEmpty);
        final readable = projectionRead.pinnedRequests.singleWhere(
          (r) => r.id == 'Bpinvisown01',
        );
        expect(readable.title, 'title-Bpinvisown01');
        expect(readable.authorId, viewer);
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
