@Tags(['pg', 'mr'])
library;

import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_projection_reader.dart';
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

/// The anchor-projection half of the constellation snapshot, extracted as a
/// helper that runs inside a caller-owned transaction. Its output must equal
/// what the `ANCHORS` snapshot read returns for the same viewer state.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_ANCHOR_PROJECTION_READER_TEST_DB',
    defaultNamePrefix: 'tentura_test_caproj',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Ucaprojview01';
  const pinnedPerson = 'Ucaprojpers01';
  const author = 'Ucaprojauth01';
  const relay = 'Ucaprojrela01';
  const blocked = 'Ucaprojblck01';
  const ctx = '';

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late ConstellationFieldRepository fieldRepository;
  late ConstellationAnchorRepository anchorRepository;
  late ConstellationAnchorProjectionReader reader;

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
    int status = 0,
  }) => db.customStatement('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$id', '$authorId', 'title-$id', 'desc', $status, true,
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

  Future<void> pin(ConstellationAnchorTarget target, double x, double y) =>
      anchorRepository.applyAnchorUpsert(
        viewerId: viewer,
        context: ctx,
        target: target,
        position: ConstellationAnchorPosition(
          xUnits: x,
          yUnits: y,
          coordinateSpaceVersion: 1,
        ),
      );

  Future<ConstellationAnchorProjection> anchorsSnapshotProjection({
    ConstellationFieldMembershipFilters filters =
        ConstellationFieldMembershipFilters.defaults,
  }) async => (await fieldRepository.readSnapshot(
    viewerId: viewer,
    context: ctx,
    params: (filters: filters, projection: ConstellationProjection.anchors),
  )).anchorProjection;

  /// The extracted reader inside a mutating repeatable-read transaction (the
  /// mode the anchor ops use).
  Future<ConstellationAnchorProjection> extractedProjectionInMutatingTx({
    ConstellationFieldMembershipFilters filters =
        ConstellationFieldMembershipFilters.defaults,
  }) => db.withMutatingRepeatableRead(
    viewer,
    () => reader.read(viewerId: viewer, context: ctx, filters: filters),
  );

  /// The extracted reader inside the read-only snapshot transaction the
  /// `ANCHORS` snapshot read itself runs in.
  Future<ConstellationAnchorProjection> extractedProjectionInReadSnapshot({
    ConstellationFieldMembershipFilters filters =
        ConstellationFieldMembershipFilters.defaults,
  }) => db.withReadSnapshot(
    () => reader.read(viewerId: viewer, context: ctx, filters: filters),
  );

  List<(String, String, double, double)> anchorPlacements(
    ConstellationAnchorProjection projection,
  ) => [
    for (final a in projection.anchors)
      (
        a.target.kind.wireValue,
        a.target.id,
        a.position.xUnits,
        a.position.yUnits,
      ),
  ];

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    db = openDisposablePgDatabase(target);
    final profiles = _PgProfileLookup(db);
    fieldRepository = ConstellationFieldRepository(db, profiles);
    anchorRepository = constellationAnchorRepositoryFor(db);
    reader = ConstellationAnchorProjectionReader(db, profiles);
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
    for (final id in [viewer, pinnedPerson, author, relay, blocked]) {
      await insertUser(id);
    }
    await reciprocalTrust(viewer, pinnedPerson);
    await reciprocalTrust(viewer, author);
    await reciprocalTrust(viewer, relay);
    await reciprocalTrust(viewer, blocked);
    await reciprocalTrust(relay, author);
  });

  final readerModes =
      <
        String,
        Future<ConstellationAnchorProjection> Function({
          ConstellationFieldMembershipFilters filters,
        })
      >{
        'mutating repeatable-read transaction': extractedProjectionInMutatingTx,
        'read-only snapshot transaction': extractedProjectionInReadSnapshot,
      };

  for (final MapEntry(key: mode, value: extractedProjection)
      in readerModes.entries) {
    group('anchor projection reader in a $mode', () {
      test(
        'equals the ANCHORS snapshot projection for a viewer with no anchors',
        () async {
          final expected = await anchorsSnapshotProjection();
          final actual = await extractedProjection();

          expect(actual, expected);
          expect(actual.anchors, isEmpty);
        },
      );

      test(
        'equals the ANCHORS snapshot projection for pinned people and Requests',
        () async {
          await insertBeacon(id: 'Bcaprojopen01', authorId: author);
          await pin(ConstellationAnchorTarget.person(pinnedPerson), 2, -1);
          await pin(ConstellationAnchorTarget.beacon('Bcaprojopen01'), -3, 4);

          final expected = await anchorsSnapshotProjection();
          final actual = await extractedProjection();

          expect(expected.pinnedPeers.map((p) => p.id), [pinnedPerson]);
          expect(expected.pinnedRequests.map((r) => r.id), ['Bcaprojopen01']);
          expect(actual, expected);
        },
      );

      test(
        'equals the ANCHORS snapshot projection with a filter-hidden pin',
        () async {
          await insertBeacon(id: 'Bcaprojopen01', authorId: author);
          await insertBeacon(id: 'Bcaprojclos01', authorId: author, status: 5);
          await insertViewerHelpOffer('Bcaprojclos01');
          await pin(ConstellationAnchorTarget.beacon('Bcaprojopen01'), 1, 1);
          await pin(ConstellationAnchorTarget.beacon('Bcaprojclos01'), 2, 2);

          final expected = await anchorsSnapshotProjection();
          final actual = await extractedProjection();

          expect(expected.serverFilteredBeaconIds, ['Bcaprojclos01']);
          expect(actual, expected);
        },
      );

      test(
        'equals the ANCHORS snapshot projection under non-default filters',
        () async {
          await insertBeacon(id: 'Bcaprojopen01', authorId: author);
          await insertBeacon(id: 'Bcaprojclos01', authorId: author, status: 5);
          await insertViewerHelpOffer('Bcaprojclos01');
          await pin(ConstellationAnchorTarget.beacon('Bcaprojopen01'), 1, 1);
          await pin(ConstellationAnchorTarget.beacon('Bcaprojclos01'), 2, 2);
          await pin(ConstellationAnchorTarget.person(pinnedPerson), 0, 3);
          const filters = ConstellationFieldMembershipFilters(
            showClosed: true,
            participatedOnly: true,
          );

          final expected = await anchorsSnapshotProjection(filters: filters);
          final actual = await extractedProjection(filters: filters);

          expect(actual, expected);
        },
      );

      test(
        'omits a pinned person who became blocked, like the snapshot read',
        () async {
          await pin(ConstellationAnchorTarget.person(blocked), 5, 5);
          await pin(ConstellationAnchorTarget.person(pinnedPerson), 1, 1);
          await db.customStatement('''
  INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
  VALUES ('$viewer', '$blocked', '$blocked')
  ''');

          final expected = await anchorsSnapshotProjection();
          final actual = await extractedProjection();

          expect(expected.pinnedPeers.map((p) => p.id), [pinnedPerson]);
          expect(actual, expected);
        },
      );
    });
  }

  group('anchor projection reader inside a caller-owned write transaction', () {
    test(
      "returns the caller's own uncommitted anchor writes with identities, "
      'positions and resolved profiles, then leaves nothing behind on rollback',
      () async {
        await pin(ConstellationAnchorTarget.person(pinnedPerson), 1, 1);
        final before = await anchorsSnapshotProjection();
        expect(before.anchors, hasLength(1));

        ConstellationAnchorProjection? inside;
        try {
          await db.withMutatingRepeatableRead(viewer, () async {
            await pin(ConstellationAnchorTarget.person(relay), 7, -7);
            await pin(ConstellationAnchorTarget.person(pinnedPerson), 2, 3);
            inside = await reader.read(
              viewerId: viewer,
              context: ctx,
              filters: ConstellationFieldMembershipFilters.defaults,
            );
            throw const _RollbackRequested();
          });
        } on _RollbackRequested {
          // Expected: forces the rollback under test.
        }

        final seen = inside!;
        expect(
          anchorPlacements(seen),
          unorderedEquals([
            ('PERSON', pinnedPerson, 2.0, 3.0),
            ('PERSON', relay, 7.0, -7.0),
          ]),
        );
        expect(
          seen.pinnedPeers.map((p) => p.id),
          unorderedEquals([pinnedPerson, relay]),
        );
        expect(seen.pinnedRequests, isEmpty);
        expect(seen.serverFilteredBeaconIds, isEmpty);
        expect(seen.revision.value, greaterThan(before.revision.value));

        final after = await anchorsSnapshotProjection();
        expect(after, before);
        expect(
          anchorPlacements(after),
          [('PERSON', pinnedPerson, 1.0, 1.0)],
        );
      },
    );

    test(
      'matches the committed ANCHORS projection once the writes commit',
      () async {
        await insertBeacon(id: 'Bcaprojopen01', authorId: author);

        ConstellationAnchorProjection? inside;
        await db.withMutatingRepeatableRead(viewer, () async {
          await pin(ConstellationAnchorTarget.person(pinnedPerson), 4, 4);
          await pin(ConstellationAnchorTarget.beacon('Bcaprojopen01'), -2, 6);
          inside = await reader.read(
            viewerId: viewer,
            context: ctx,
            filters: ConstellationFieldMembershipFilters.defaults,
          );
        });

        final committed = await anchorsSnapshotProjection();
        expect(inside, committed);
        expect(committed.anchors, hasLength(2));
      },
    );
  });
}

/// Thrown inside the outer transaction to force its rollback.
final class _RollbackRequested implements Exception {
  const _RollbackRequested();
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
          myVote: null,
          isMutualFriend: reciprocalPeerIds.contains(entry.key),
          subjectExplicitlyTrustsViewer: trustsViewerPeerIds.contains(
            entry.key,
          ),
          scores: const [],
          userAvailability: null,
        ),
    };
  }
}
