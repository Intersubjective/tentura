@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
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

/// A constellation snapshot transaction decides whether the viewer may read a
/// pinned Request once and reuses the answer when it hydrates the pinned
/// Requests and the post feed. It also fetches each peer profile once across
/// the anchor projection and the rest of a FULL read.
///
/// `beacon_can_read_content` is wrapped by a counting function that takes a
/// session-level advisory lock (classid = the beacon id's non-negative hash,
/// fresh objid per call) because a function call made inside the read-only
/// snapshot transaction leaves no other trace; locks survive the transaction
/// and are counted through `pg_locks`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_PINNED_READABILITY_REUSE_TEST_DB',
    defaultNamePrefix: 'tentura_test_cpinread',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Ucpinreadview01';
  const author = 'Ucpinreadauth01';
  const bystander = 'Ucpinreadbyst01';
  const blockedAuthor = 'Ucpinreadblck01';
  const ctx = '';
  const peerRequest = 'Bcpinreadpeer01';
  const ownRequest = 'Bcpinreadown001';
  const closedRequest = 'Bcpinreadclos01';
  const ownPost = 'Bcpinreadpost01';

  /// Closed Request of another author that the viewer never took part in:
  /// not readable.
  const hiddenClosedRequest = 'Bcpinreadhidd01';

  /// Open Request whose author the viewer blocked: not readable.
  const blockedAuthorRequest = 'Bcpinreadblkd01';
  const allPinned = [
    peerRequest,
    ownRequest,
    closedRequest,
    ownPost,
    hiddenClosedRequest,
    blockedAuthorRequest,
  ];

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late _RecordingProfileLookup profiles;
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

  Future<void> insertBeacon({
    required String id,
    required String authorId,
    int kind = 0,
    int status = 0,
  }) => db.customStatement('''
INSERT INTO public.beacon (
  id, user_id, title, description, kind, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$id', '$authorId', '${kind == 0 ? 'title-$id' : ''}',
  '${kind == 0 ? 'desc' : ''}', $kind, $status, ${kind == 0},
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status
''');

  /// A closed Request is only readable (so pinnable) for a participant.
  Future<void> insertViewerHelpOffer(String beaconId) => db.customStatement('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status, created_at, updated_at)
VALUES ('$beaconId', '$viewer', 'offer', 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (beacon_id, user_id) DO NOTHING
''');

  Future<void> pinBeacon(String id, double x) => anchorRepository.applyAnchorUpsert(
    viewerId: viewer,
    context: ctx,
    target: ConstellationAnchorTarget.beacon(id),
    position: ConstellationAnchorPosition(
      xUnits: x,
      yUnits: 1,
      coordinateSpaceVersion: 1,
    ),
  );

  /// Pins a beacon the viewer can no longer read, e.g. one pinned while it
  /// was readable. [pinBeacon] refuses such targets, so the row is written
  /// directly.
  Future<void> pinUnreadableBeacon(String id, double x) =>
      db.customStatement('''
INSERT INTO public.constellation_anchor (
  id, viewer_id, beacon_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (
  'CA$id', '$viewer', '$id', $x, 1, 1, 0, 'epoch'::timestamptz
)
''');

  Future<int> readabilityCalls(String beaconId) async {
    final rows = await writer.execute(
      "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' "
      "AND classid::bigint = (hashtext('$beaconId') & 2147483647) "
      'AND database = '
      '(SELECT oid FROM pg_database WHERE datname = current_database())',
    );
    return rows.single.single! as int;
  }

  /// Runs [read] and returns how many times each of [beaconIds] was checked
  /// for content readability while it ran.
  Future<Map<String, int>> readabilityCallsDuring(
    List<String> beaconIds,
    Future<void> Function() read,
  ) async {
    final before = {
      for (final id in beaconIds) id: await readabilityCalls(id),
    };
    await read();
    return {
      for (final id in beaconIds) id: await readabilityCalls(id) - before[id]!,
    };
  }

  Future<ConstellationFieldSnapshot> readSnapshot({
    required ConstellationProjection projection,
    ConstellationFieldMembershipFilters filters =
        ConstellationFieldMembershipFilters.defaults,
  }) => fieldRepository.readSnapshot(
    viewerId: viewer,
    context: ctx,
    params: (filters: filters, projection: projection),
  );

  // Puts the production function back under its own name; a no-op when the
  // counting wrapper is not installed, so an interrupted earlier run cannot
  // make the next setup fail.
  Future<void> restoreReadabilityFunction() => writer.execute(r'''
DO $$
BEGIN
  IF to_regprocedure('public._cpinread_can_read_content_impl(text, text)')
      IS NOT NULL THEN
    DROP FUNCTION public.beacon_can_read_content(text, text);
    ALTER FUNCTION public._cpinread_can_read_content_impl(text, text)
      RENAME TO beacon_can_read_content;
  END IF;
END;
$$
''');

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    db = openDisposablePgDatabase(target);
    profiles = _RecordingProfileLookup(db);
    fieldRepository = ConstellationFieldRepository(db, profiles);
    anchorRepository = constellationAnchorRepositoryFor(db);

    await restoreReadabilityFunction();
    await writer.execute(
      'ALTER FUNCTION public.beacon_can_read_content(text, text) '
      'RENAME TO _cpinread_can_read_content_impl',
    );
    await writer.execute(r'''
CREATE FUNCTION public.beacon_can_read_content(p_beacon_id text, p_viewer_id text)
RETURNS boolean LANGUAGE plpgsql VOLATILE AS $$
BEGIN
  PERFORM pg_advisory_lock(
    (hashtext(p_beacon_id) & 2147483647), (random() * 1000000000)::int);
  RETURN public._cpinread_can_read_content_impl(p_beacon_id, p_viewer_id);
END;
$$
''');
  });

  tearDownAll(() async {
    await restoreReadabilityFunction();
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  setUp(() async {
    profiles.requestedIds.clear();
    await db.customStatement('DELETE FROM public.constellation_anchor');
    await db.customStatement('DELETE FROM public.constellation_anchor_cursor');
    await db.customStatement('DELETE FROM public.beacon');
    await db.customStatement('DELETE FROM public.user_block');
    await db.customStatement('DELETE FROM public.vote_user');
    await db.customStatement('DELETE FROM public."user"');
    for (final id in [viewer, author, bystander, blockedAuthor]) {
      await insertUser(id);
    }
    await reciprocalTrust(viewer, author);
    await reciprocalTrust(viewer, bystander);
    await insertBeacon(id: peerRequest, authorId: author);
    await insertBeacon(id: ownRequest, authorId: viewer);
    await insertBeacon(id: closedRequest, authorId: author, status: 5);
    await insertViewerHelpOffer(closedRequest);
    await insertBeacon(id: ownPost, authorId: viewer, kind: 1);
    await db.customStatement('''
INSERT INTO public.beacon_pinned (user_id, beacon_id)
VALUES ('$viewer', '$ownPost')
''');
    await pinBeacon(peerRequest, 1);
    await pinBeacon(ownRequest, 2);
    await pinBeacon(closedRequest, 3);
    await pinBeacon(ownPost, 4);
    await insertBeacon(id: hiddenClosedRequest, authorId: author, status: 5);
    await insertBeacon(id: blockedAuthorRequest, authorId: blockedAuthor);
    await db.customStatement('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$viewer', '$blockedAuthor', '$viewer')
''');
    await pinUnreadableBeacon(hiddenClosedRequest, 5);
    await pinUnreadableBeacon(blockedAuthorRequest, 6);
  });

  group('pinned Request readability within one snapshot transaction', () {
    test(
      'a FULL read checks content readability once per pinned beacon',
      () async {
        const pinned = allPinned;

        final calls = await readabilityCallsDuring(
          pinned,
          () => readSnapshot(projection: ConstellationProjection.full),
        );

        expect(calls, {for (final id in pinned) id: 1});
      },
    );

    test(
      'an ANCHORS read checks content readability once per pinned beacon',
      () async {
        const pinned = allPinned;

        final calls = await readabilityCallsDuring(
          pinned,
          () => readSnapshot(projection: ConstellationProjection.anchors),
        );

        expect(calls, {for (final id in pinned) id: 1});
      },
    );

    test(
      'a FULL read under non-default filters still checks each pinned beacon '
      'once',
      () async {
        const pinned = allPinned;

        final calls = await readabilityCallsDuring(
          pinned,
          () => readSnapshot(
            projection: ConstellationProjection.full,
            filters: const ConstellationFieldMembershipFilters(
              showClosed: true,
              participatedOnly: true,
            ),
          ),
        );

        expect(calls, {for (final id in pinned) id: 1});
      },
    );

    test(
      'each successive read checks a pinned Request once in its own transaction',
      () async {
        final pinned = [peerRequest];
        await readSnapshot(projection: ConstellationProjection.full);

        final calls = await readabilityCallsDuring(
          pinned,
          () => readSnapshot(projection: ConstellationProjection.full),
        );

        expect(calls, {peerRequest: 1});
      },
    );
  });

  // Reuse must preserve the rev 10 section 5.10 content contract: readable
  // lifecycle pins keep their content; inaccessible pins carry identity only.
  group('FULL snapshot content with transaction-local reuse', () {
    test(
      'lists the pinned Requests, peers and posts of the fixtures',
      () async {
        final snapshot = await readSnapshot(
          projection: ConstellationProjection.full,
        );

        final projection = snapshot.anchorProjection;
        expect(
          projection.pinnedRequests.map((r) => r.id),
          unorderedEquals(allPinned),
        );
        final wrappingUp = projection.pinnedRequests.singleWhere(
          (r) => r.id == closedRequest,
        );
        expect(wrappingUp.pinState, 'wrappingUp');
        expect(wrappingUp.authorId, author);
        expect(wrappingUp.title, 'title-$closedRequest');
        expect(wrappingUp.isPlaceholder, isFalse);
        expect(projection.serverFilteredBeaconIds, [closedRequest]);
        expect(
          snapshot.peers.map((p) => p.id),
          unorderedEquals([viewer, author, bystander]),
        );
        expect(snapshot.posts.map((p) => p.id), [ownPost]);
        expect(
          snapshot.peers.map((p) => p.id),
          isNot(contains(blockedAuthor)),
        );
        expect(snapshot.posts.single.isPinned, isTrue);
        expect(
          snapshot.requests.map((r) => r.id),
          unorderedEquals([ownRequest]),
        );
      },
    );

    test(
      'retains inaccessible pins as placeholders without exposing their content',
      () async {
        final snapshot = await readSnapshot(
          projection: ConstellationProjection.full,
        );

        const unreadable = [hiddenClosedRequest, blockedAuthorRequest];
        final projection = snapshot.anchorProjection;
        final listed = <String>{
          ...projection.serverFilteredBeaconIds,
          ...snapshot.requests.map((r) => r.id),
          ...snapshot.posts.map((p) => p.id),
        };
        for (final id in unreadable) {
          expect(listed, isNot(contains(id)), reason: id);
          expect(projection.anchors.map((a) => a.target.id), contains(id));
          final placeholder = projection.pinnedRequests.singleWhere(
            (r) => r.id == id,
          );
          expect(
            placeholder.pinState,
            id == blockedAuthorRequest ? 'blockedByMe' : 'noAccess',
          );
          expect(placeholder.isPlaceholder, isTrue);
          expect(placeholder.title, isEmpty);
          expect(placeholder.authorId, isEmpty);
          expect(placeholder.needs, isEmpty);
          expect(placeholder.addressLabel, isNull);
          expect(placeholder.coverThumb, isNull);
          expect(placeholder.isMine, isFalse);
          expect(placeholder.parentBeaconId, isNull);
        }
        expect(snapshot.peers.map((p) => p.id), isNot(contains(blockedAuthor)));
      },
    );

    test(
      'checks each unreadable pinned Request once while returning its placeholder',
      () async {
        final calls = await readabilityCallsDuring(
          const [hiddenClosedRequest, blockedAuthorRequest],
          () => readSnapshot(projection: ConstellationProjection.full),
        );

        expect(calls, {hiddenClosedRequest: 1, blockedAuthorRequest: 1});
      },
    );

    test('has the same anchor projection as an ANCHORS read', () async {
      final full = await readSnapshot(projection: ConstellationProjection.full);
      final anchors = await readSnapshot(
        projection: ConstellationProjection.anchors,
      );

      expect(full.anchorProjection, anchors.anchorProjection);
    });
  });

  group('peer profiles within one snapshot transaction', () {
    test('a FULL read requests each peer profile once', () async {
      await readSnapshot(projection: ConstellationProjection.full);
      profiles.requestedIds.clear();

      final snapshot = await readSnapshot(
        projection: ConstellationProjection.full,
      );

      final requested = profiles.requestedIds;
      expect(requested, isNotEmpty);
      expect(requested.toSet(), hasLength(requested.length));
      expect(
        requested.toSet().containsAll(snapshot.peers.map((p) => p.id)),
        isTrue,
        reason:
            'requested $requested for peers '
            '${snapshot.peers.map((p) => p.id).toList()}',
      );
    });

    test('an ANCHORS read requests each peer profile once', () async {
      final snapshot = await readSnapshot(
        projection: ConstellationProjection.anchors,
      );

      final projection = snapshot.anchorProjection;
      final anchorPeerIds = {
        ...projection.pinnedPeers.map((p) => p.id),
        ...projection.supportPeers.map((p) => p.id),
        for (final request in projection.pinnedRequests)
          if (!request.isPlaceholder) request.authorId,
      };
      final requested = profiles.requestedIds;
      expect(requested, isNotEmpty);
      expect(requested.toSet(), hasLength(requested.length));
      expect(requested.toSet().containsAll(anchorPeerIds), isTrue);
      expect(requested, isNot(contains('')));
      expect(requested, isNot(contains(blockedAuthor)));
    });
  });
}

/// Avoids GetIt-backed presence mapping in pg tests and records every id the
/// constellation read asks for.
final class _RecordingProfileLookup implements UserProfileBatchLookup {
  _RecordingProfileLookup(this._database);

  final TenturaDb _database;

  final requestedIds = <String>[];

  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) {
    final asked = ids.toList();
    requestedIds.addAll(asked);
    return constellationProfilesFromRecords(this, asked);
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
