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

import '../../support/disposable_pg_target.dart';

/// The discoverable-Request section of the constellation FULL snapshot: peers'
/// published, discoverable Requests the viewer may read, in
/// `(author id, Request id)` order, capped at [kConstellationRequestCap] with a
/// cap-plus-one probe for the `requestsCapped` flag.
///
/// Authorization is applied before the cap, so a rejected candidate is never
/// returned and never occupies a cap slot; and the scan must reach the cap
/// without asking the readability function about every candidate.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_DISCOVERABLE_KEYSET_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_cdkeyset',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Ucdkviewer001';
  const ctx = '';
  const cap = kConstellationRequestCap;

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late ConstellationFieldRepository repository;
  late ConstellationAnchorRepository anchorRepository;

  Future<void> insertPeer(String id, {bool trusted = true}) async {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');
    if (trusted) {
      await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewer', '$id', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$id', '$viewer', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');
    }
  }

  /// [count] Requests by [author], ids `B<tag><nnnn>`.
  Future<void> insertRequests({
    required String author,
    required String tag,
    required int count,
    int status = 0,
    bool discoverable = true,
    bool published = true,
    bool denied = false,
  }) => writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
)
SELECT 'B$tag' || lpad(i::text, 4, '0'), '$author', 'title',
       '${denied ? 'denied' : 'desc'}', $status,
       $discoverable,
       ${published ? "'2026-01-01T00:00:00Z'" : 'NULL'},
       '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
FROM generate_series(1, $count) AS i
''');

  Future<void> authorBlocksViewer(String author) => writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$author', '$viewer', '$viewer')
ON CONFLICT DO NOTHING
''');

  Future<void> viewerBlocksAuthor(String author) => writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$viewer', '$author', '$author')
ON CONFLICT DO NOTHING
''');

  Future<void> offerHelp(String beaconId) => writer.execute('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status, created_at, updated_at)
VALUES ('$beaconId', '$viewer', 'offer', 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (beacon_id, user_id) DO NOTHING
''');

  /// Reference answer: the unbatched shape of the discoverable query (filter
  /// on authorization, order by `(user_id, id)`, LIMIT cap + 1), run on its own
  /// connection outside the snapshot read.
  Future<List<String>> referenceIds({
    List<int> statuses = const [0, 7, 8],
    Set<String> excluded = const {},
    bool participatedOnly = false,
  }) async {
    final rows = await writer.execute(
      Sql.named('''
SELECT b.id
FROM public.beacon b
WHERE b.user_id = ANY(public.person_visible_peer_ids_tx(@viewer, @ctx))
  AND b.user_id <> @viewer
  AND b.is_discoverable
  AND b.kind = 0
  AND b.status = ANY(@statuses::int[])
  AND b.published_at IS NOT NULL
  AND public.beacon_can_read_content(b.id, @viewer)
  AND NOT public.block_hides(@viewer, b.user_id)
  AND NOT public.block_hides(b.user_id, @viewer)
  AND NOT (b.id = ANY(@excluded::text[]))
  ${participatedOnly ? '''
  AND EXISTS (
    SELECT 1 FROM public.beacon_help_offer ho
    WHERE ho.beacon_id = b.id AND ho.user_id = @viewer AND ho.status = 0
  )''' : ''}
ORDER BY b.user_id, b.id
LIMIT ${cap + 1}
'''),
      parameters: {
        'viewer': viewer,
        'ctx': ctx,
        'statuses': statuses,
        'excluded': excluded.toList(),
      },
    );
    return [for (final row in rows) row.first! as String];
  }

  Future<ConstellationFieldSnapshot> readField({
    ConstellationFieldMembershipFilters filters =
        ConstellationFieldMembershipFilters.defaults,
  }) => repository.readSnapshot(
    viewerId: viewer,
    context: ctx,
    params: (filters: filters, projection: ConstellationProjection.full),
  );

  /// Requests of the snapshot that are not the viewer's own.
  List<String> peerRequestIds(ConstellationFieldSnapshot snapshot) => [
    for (final request in snapshot.requests)
      if (request.authorId != viewer) request.id,
  ];

  // Readability probe: the verdict functions are wrapped so every candidate a
  // query asks about bumps a session-level counter setting (settable in a
  // read-only transaction, unlike a sequence). The per-row function counts one
  // per call, the set-based companion one per id passed in. The Drift pool is
  // a single connection, so the counter is read back through [db].
  Future<void> installReadabilityProbe() async {
    await writer.execute(
      'ALTER FUNCTION public.beacon_can_read_content(text, text) '
      'RENAME TO beacon_can_read_content_unprobed',
    );
    await writer.execute(r"""
CREATE FUNCTION public.beacon_can_read_content(p_beacon_id text, p_viewer_id text)
RETURNS boolean LANGUAGE plpgsql STABLE COST 1000 AS $$
BEGIN
  PERFORM set_config('probe.asked',
    (coalesce(nullif(current_setting('probe.asked', true), ''), '0')::int + 1)::text,
    false);
  IF EXISTS (
    SELECT 1 FROM public.beacon WHERE id = p_beacon_id AND description = 'denied'
  ) THEN
    RETURN false;
  END IF;
  RETURN public.beacon_can_read_content_unprobed(p_beacon_id, p_viewer_id);
END
$$
""");
    await writer.execute(
      'ALTER FUNCTION public.beacon_readable_ids(text, text[]) '
      'RENAME TO beacon_readable_ids_unprobed',
    );
    await writer.execute(r"""
CREATE FUNCTION public.beacon_readable_ids(p_viewer_id text, p_ids text[])
RETURNS SETOF text LANGUAGE plpgsql STABLE AS $$
BEGIN
  PERFORM set_config('probe.asked',
    (coalesce(nullif(current_setting('probe.asked', true), ''), '0')::int
      + coalesce(cardinality(p_ids), 0))::text,
    false);
  RETURN QUERY
  SELECT r FROM public.beacon_readable_ids_unprobed(p_viewer_id, p_ids) AS r
  WHERE NOT EXISTS (
    SELECT 1 FROM public.beacon WHERE id = r AND description = 'denied'
  );
END
$$
""");
  }

  Future<void> resetReadabilityProbe() =>
      db.customStatement("SELECT set_config('probe.asked', '0', false)");

  Future<int> readabilityVerdictsAsked() async {
    final row = await db
        .customSelect(
          "SELECT coalesce(nullif(current_setting('probe.asked', true), ''), "
          "'0')::int AS n",
        )
        .getSingle();
    return row.read<int>('n');
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    db = openDisposablePgDatabase(target);
    repository = ConstellationFieldRepository(db, _PgProfileLookup(db));
    anchorRepository = ConstellationAnchorRepository(db);
    await installReadabilityProbe();
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  setUp(() async {
    await writer.execute('DELETE FROM public.constellation_anchor');
    await writer.execute('DELETE FROM public.constellation_anchor_cursor');
    await writer.execute('DELETE FROM public.beacon_help_offer');
    await writer.execute('DELETE FROM public.beacon');
    await writer.execute('DELETE FROM public.user_block');
    await writer.execute('DELETE FROM public.vote_user');
    await writer.execute('DELETE FROM public."user"');
    await insertPeer(viewer, trusted: false);
    await resetReadabilityProbe();
  });

  group('discoverable Requests of the FULL snapshot', () {
    test('come in author-then-Request id order and stop at the cap, '
        'flagging that more exist', () async {
      for (final author in ['Ucdkauth03', 'Ucdkauth01', 'Ucdkauth02']) {
        await insertPeer(author);
        await insertRequests(author: author, tag: author, count: 70);
      }

      final snapshot = await readField();

      final expected = await referenceIds();
      expect(expected.length, cap + 1, reason: 'fixture exceeds the cap');
      expect(peerRequestIds(snapshot), expected.take(cap).toList());
      expect(snapshot.requestsCapped, isTrue);
    });

    test('exactly cap eligible Requests are all returned and not flagged '
        'as capped; one more is flagged', () async {
      await insertPeer('Ucdkauth01');
      await insertRequests(author: 'Ucdkauth01', tag: 'a', count: cap);

      final atCap = await readField();
      expect(peerRequestIds(atCap), await referenceIds());
      expect(peerRequestIds(atCap), hasLength(cap));
      expect(atCap.requestsCapped, isFalse);

      await insertRequests(author: 'Ucdkauth01', tag: 'b', count: 1);

      final overCap = await readField();
      expect(peerRequestIds(overCap), hasLength(cap));
      expect(overCap.requestsCapped, isTrue);
    });

    test(
      'a long run of rejected candidates ahead of the eligible ones does '
      'not shorten or reorder the result, and none of it is returned',
      () async {
        // Three authors whose Requests the viewer may not read sort first and
        // hold more candidates than any single readability batch can cover.
        for (final author in ['Ucdka1reject', 'Ucdka2reject', 'Ucdka3reject']) {
          await insertPeer(author);
          await insertRequests(
            author: author,
            tag: author,
            count: 200,
            denied: true,
          );
        }
        for (final author in ['Ucdkb1ok', 'Ucdkb2ok']) {
          await insertPeer(author);
          await insertRequests(author: author, tag: author, count: 90);
        }

        final snapshot = await readField();

        final ids = peerRequestIds(snapshot);
        expect(ids, await referenceIds().then((r) => r.take(cap).toList()));
        expect(ids, hasLength(cap));
        expect(snapshot.requestsCapped, isTrue);
        final authors = snapshot.requests.map((r) => r.authorId).toSet();
        expect(
          authors.intersection({
            'Ucdka1reject',
            'Ucdka2reject',
            'Ucdka3reject',
          }),
          isEmpty,
        );
      },
    );

    test('rejected candidates interleaved between eligible authors never '
        'occupy a cap slot', () async {
      for (var i = 0; i < 12; i++) {
        final author = 'Ucdkmix${i.toString().padLeft(2, '0')}';
        await insertPeer(author);
        await insertRequests(
          author: author,
          tag: author,
          count: 30,
          denied: i % 4 == 1,
        );
        if (i % 4 == 3) await authorBlocksViewer(author);
      }

      final snapshot = await readField();

      final expected = await referenceIds();
      expect(peerRequestIds(snapshot), expected.take(cap).toList());
      expect(snapshot.requestsCapped, expected.length > cap);
      for (final request in snapshot.requests) {
        final index = int.parse(request.authorId.substring('Ucdkmix'.length));
        expect(index.isEven, isTrue, reason: request.id);
      }
    });

    test('a population where every candidate is rejected yields no Requests '
        'and is not flagged as capped', () async {
      for (var i = 0; i < 4; i++) {
        final author = 'Ucdkrej0$i';
        await insertPeer(author);
        await insertRequests(
          author: author,
          tag: author,
          count: 120,
          denied: i == 0 || i == 3,
        );
        if (i == 1) await authorBlocksViewer(author);
        if (i == 2) await viewerBlocksAuthor(author);
      }

      final snapshot = await readField();

      expect(peerRequestIds(snapshot), isEmpty);
      expect(snapshot.requestsCapped, isFalse);
    });

    test('hidden, unpublished and out-of-lifecycle Requests are not '
        'returned', () async {
      await insertPeer('Ucdkauth01');
      await insertRequests(author: 'Ucdkauth01', tag: 'open', count: 5);
      await insertRequests(
        author: 'Ucdkauth01',
        tag: 'hid',
        count: 5,
        discoverable: false,
      );
      await insertRequests(
        author: 'Ucdkauth01',
        tag: 'unp',
        count: 5,
        published: false,
      );
      await insertRequests(
        author: 'Ucdkauth01',
        tag: 'cls',
        count: 5,
        status: 5,
      );
      await insertRequests(
        author: 'Ucdkauth01',
        tag: 'can',
        count: 5,
        status: 1,
      );

      final snapshot = await readField();

      expect(peerRequestIds(snapshot), await referenceIds());
      expect(
        peerRequestIds(snapshot),
        [for (var i = 1; i <= 5; i++) 'Bopen000$i'],
      );
    });

    test('showClosed admits closed-lifecycle Requests the viewer can read '
        'through participation', () async {
      await insertPeer('Ucdkauth01');
      await insertRequests(author: 'Ucdkauth01', tag: 'open', count: 3);
      await insertRequests(
        author: 'Ucdkauth01',
        tag: 'cls',
        count: 3,
        status: 5,
      );
      await offerHelp('Bcls0002');

      final snapshot = await readField(
        filters: const ConstellationFieldMembershipFilters(showClosed: true),
      );

      expect(
        peerRequestIds(snapshot),
        await referenceIds(statuses: const [0, 7, 8, 5, 4, 6]),
      );
      expect(peerRequestIds(snapshot), contains('Bcls0002'));
      expect(peerRequestIds(snapshot), isNot(contains('Bcls0001')));
    });

    test('participatedOnly keeps only Requests the viewer participates in, '
        'even when they are far down the candidate order', () async {
      for (final author in ['Ucdkauth01', 'Ucdkauth02']) {
        await insertPeer(author);
        await insertRequests(author: author, tag: author, count: 160);
      }
      await offerHelp('BUcdkauth020150');

      final snapshot = await readField(
        filters: const ConstellationFieldMembershipFilters(
          participatedOnly: true,
        ),
      );

      expect(peerRequestIds(snapshot), ['BUcdkauth020150']);
      expect(
        peerRequestIds(snapshot),
        await referenceIds(participatedOnly: true),
      );
      expect(snapshot.requestsCapped, isFalse);
    });

    test('a pinned Request is left out of the discoverable section and does '
        'not use up a cap slot', () async {
      await insertPeer('Ucdkauth01');
      await insertRequests(author: 'Ucdkauth01', tag: 'a', count: cap + 1);
      await anchorRepository.upsertAnchor(
        viewerId: viewer,
        context: ctx,
        target: ConstellationAnchorTarget.beacon('Ba0001'),
        position: const ConstellationAnchorPosition(
          xUnits: 1,
          yUnits: 1,
          coordinateSpaceVersion: 1,
        ),
      );

      final snapshot = await readField();

      expect(peerRequestIds(snapshot), isNot(contains('Ba0001')));
      expect(
        peerRequestIds(snapshot),
        await referenceIds(excluded: const {'Ba0001'}).then(
          (r) => r.take(cap).toList(),
        ),
      );
      expect(peerRequestIds(snapshot), hasLength(cap));
      expect(snapshot.requestsCapped, isFalse);
    });

    test('the Requests-only read agrees with the snapshot section for the '
        'same viewer state', () async {
      for (final author in ['Ucdkauth01', 'Ucdkauth02']) {
        await insertPeer(author);
        await insertRequests(author: author, tag: author, count: 40);
      }
      await authorBlocksViewer('Ucdkauth01');

      final snapshot = await readField();
      final records = await repository.discoverableRequests(
        viewerId: viewer,
        context: ctx,
        cap: cap,
      );

      expect(peerRequestIds(snapshot), [for (final r in records) r.id]);
    });
  });

  group('discoverable candidate scan work', () {
    test('an all-readable population is read without asking about every '
        'candidate once the cap is reached', () async {
      for (var i = 0; i < 30; i++) {
        final author = 'Ucdkwide${i.toString().padLeft(2, '0')}';
        await insertPeer(author);
        await insertRequests(author: author, tag: author, count: 100);
      }
      await writer.execute('ANALYZE public.beacon');
      await resetReadabilityProbe();

      final snapshot = await readField();

      expect(peerRequestIds(snapshot), hasLength(cap));
      expect(snapshot.requestsCapped, isTrue);
      final asked = await readabilityVerdictsAsked();
      expect(
        asked,
        lessThanOrEqualTo(2 * (cap + 1)),
        reason:
            '3000 candidates, all readable: the scan should stop shortly '
            'after cap + 1 eligible rows, not examine all of them',
      );
    });

    test('a sparse readable population is found with every candidate asked '
        'about at most once', () async {
      for (var i = 0; i < 30; i++) {
        final author = 'Ucdksprs${i.toString().padLeft(2, '0')}';
        await insertPeer(author);
        await insertRequests(
          author: author,
          tag: author,
          count: 100,
          denied: i % 10 != 9,
        );
      }
      await writer.execute('ANALYZE public.beacon');
      await resetReadabilityProbe();

      final snapshot = await readField();

      final expected = await referenceIds();
      expect(peerRequestIds(snapshot), expected.take(cap).toList());
      expect(peerRequestIds(snapshot), hasLength(cap));
      final asked = await readabilityVerdictsAsked();
      expect(
        asked,
        lessThanOrEqualTo(3000),
        reason: 'every candidate is examined at most once',
      );
    });

    test('rejected candidates behind the cap are never examined', () async {
      await insertPeer('Ucdkhead');
      await insertRequests(author: 'Ucdkhead', tag: 'h', count: cap + 20);
      await insertPeer('Ucdktail');
      await insertRequests(
        author: 'Ucdktail',
        tag: 't',
        count: 2000,
        denied: true,
      );
      await writer.execute('ANALYZE public.beacon');
      await resetReadabilityProbe();

      final snapshot = await readField();

      expect(peerRequestIds(snapshot), hasLength(cap));
      expect(snapshot.requestsCapped, isTrue);
      expect(snapshot.requests.map((r) => r.authorId).toSet(), {'Ucdkhead'});
      final asked = await readabilityVerdictsAsked();
      expect(
        asked,
        lessThanOrEqualTo(4 * (cap + 1)),
        reason:
            'the denied candidates sort after the cap is filled and '
            'must never be examined; allow a few batches of overfetch',
      );
    });
  });
}

final class _PgProfileLookup implements UserProfileBatchLookup {
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
