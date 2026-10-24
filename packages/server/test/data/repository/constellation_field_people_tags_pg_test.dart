@Tags(['pg'])
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

/// People tags and first-seen markers in the Field snapshot (#699): each peer
/// carries the viewer's own tag ids and the automatic tag kinds, and the
/// snapshot records who the viewer has now seen.
Future<void> main() async {
  test('the Field peer cap is 400', () {
    expect(kConstellationPeerCap, 400);
  });

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_PEOPLE_TAGS_TEST_DB',
    defaultNamePrefix: 'tentura_test_fieldtags',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Uftviewer001';
  const ctx = '';

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late ConstellationFieldRepository repository;

  Future<void> insertUser(String id) => db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', 'name-$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

  Future<void> mutualTrust(String a, String b) => db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$a', '$b', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$b', '$a', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

  Future<void> addPeer(String id) async {
    await insertUser(id);
    await mutualTrust(viewer, id);
  }

  Future<void> tag(String tagId, String ownerId, List<String> people) async {
    await db.customStatement('''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES ('$tagId', '$ownerId', 'name-$tagId', 'g', 0, 0)
''');
    for (final person in people) {
      await db.customStatement('''
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
VALUES ('$tagId', '$ownerId', '$person', 0)
''');
    }
  }

  Future<ConstellationFieldSnapshot> read([
    ConstellationFieldRepository? from,
  ]) => (from ?? repository).readSnapshot(
    viewerId: viewer,
    context: ctx,
    params: (
      filters: ConstellationFieldMembershipFilters.defaults,
      projection: ConstellationProjection.full,
    ),
  );

  Set<int> kindsOf(ConstellationPeerRecord peer) => peer.autoTagKinds.toSet();

  Future<int> firstSeenWrites() async =>
      (await db
              .customSelect('SELECT n FROM public.first_seen_insert_counter')
              .getSingle())
          .read<int>('n');

  Future<Map<String, String>> firstSeenRows() async => {
    for (final row in await db.customSelect('''
SELECT peer_id, first_seen_at::text AS at
FROM public.person_field_first_seen WHERE viewer_id = '$viewer'
''').get())
      row.read<String>('peer_id'): row.read<String>('at'),
  };

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    db = openDisposablePgDatabase(target);
    repository = ConstellationFieldRepository(db, _PgProfileLookup(db));
    // Counts INSERT statements on the first-seen table, including ones that
    // insert no row, so it sees every write transaction the snapshot opens.
    await db.customStatement(
      'CREATE TABLE public.first_seen_insert_counter (n int NOT NULL)',
    );
    await db.customStatement(
      'INSERT INTO public.first_seen_insert_counter VALUES (0)',
    );
    await db.customStatement(r'''
CREATE FUNCTION public.first_seen_insert_count() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.first_seen_insert_counter SET n = n + 1;
  RETURN NULL;
END $$
''');
    await db.customStatement('''
CREATE TRIGGER first_seen_insert_count AFTER INSERT
ON public.person_field_first_seen
FOR EACH STATEMENT EXECUTE FUNCTION public.first_seen_insert_count()
''');
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  setUp(() async {
    // A beacon must keep its owner (beacon_owner_or_deleted_ck), so the user
    // delete below cannot null it out from under it.
    await db.customStatement('DELETE FROM public.beacon');
    await db.customStatement('DELETE FROM public."user"');
    await db.customStatement(
      'UPDATE public.first_seen_insert_counter SET n = 0',
    );
    await insertUser(viewer);
  });

  group('own tags on Field peers', () {
    test('lists only the viewer tags, never another owner tags on the same '
        'person', () async {
      const tagged = 'Uftpeertag01';
      const untagged = 'Uftpeerplain';
      const other = 'Uftotherown1';
      await addPeer(tagged);
      await addPeer(untagged);
      await addPeer(other);
      await tag('Tftmine00001', viewer, [tagged]);
      await tag('Tftmine00002', viewer, [tagged]);
      await tag('Tftother0001', other, [tagged, untagged]);

      final snapshot = await read();

      final byId = {for (final p in snapshot.peers) p.id: p};
      expect(
        byId[tagged]!.ownTagIds.toSet(),
        {'Tftmine00001', 'Tftmine00002'},
      );
      expect(byId[untagged]!.ownTagIds, isEmpty);
    });
  });

  group('automatic tag kinds on Field peers', () {
    test('match the automatic tags the viewer has for those people', () async {
      const mutualOnly = 'Uftautomut01';
      const forwarded = 'Uftautofwd01';
      await addPeer(mutualOnly);
      await addPeer(forwarded);
      await db.customStatement('''
INSERT INTO public.beacon (id, user_id, title, description, status,
  is_discoverable, published_at, created_at, updated_at, last_activity_at)
VALUES ('Bftautofwd01', '$viewer', 't', 'd', 0, true, now(), now(), now(), now())
''');
      await db.customStatement('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('Bftautofwd01', '$viewer', '$forwarded')
''');

      final snapshot = await read();

      final expected = <String, Set<int>>{};
      for (final row in await db.customSelect('''
SELECT peer_id, kind::int AS kind
FROM public.person_auto_tags('$viewer', ARRAY['$mutualOnly', '$forwarded'])
''').get()) {
        (expected[row.read<String>('peer_id')] ??= {}).add(
          row.read<int>('kind'),
        );
      }
      final byId = {for (final p in snapshot.peers) p.id: p};
      expect(expected[forwarded], containsAll({0, 7}));
      expect(kindsOf(byId[mutualOnly]!), expected[mutualOnly]);
      expect(kindsOf(byId[forwarded]!), expected[forwarded]);
    });
  });

  group('first seen on Field peers', () {
    test('first read backfills at -infinity so nobody is New on the second '
        'read, and a later arrival is New', () async {
      const early1 = 'Uftseenear01';
      const early2 = 'Uftseenear02';
      const late = 'Uftseenlate1';
      await addPeer(early1);
      await addPeer(early2);

      final first = await read();
      expect(first.peers.map((p) => p.id), containsAll([early1, early2]));
      expect(await firstSeenRows(), {
        early1: '-infinity',
        early2: '-infinity',
      });

      final second = await read();
      for (final peer in second.peers) {
        expect(kindsOf(peer), isNot(contains(8)), reason: peer.id);
      }

      await addPeer(late);
      await read();
      final rows = await firstSeenRows();
      expect(rows[early1], '-infinity');
      expect(rows[late], isNotNull);
      expect(rows[late], isNot('-infinity'));

      final fourth = await read();
      final byId = {for (final p in fourth.peers) p.id: p};
      expect(kindsOf(byId[late]!), contains(8));
      expect(kindsOf(byId[early1]!), isNot(contains(8)));
      expect(byId[late]!.firstSeenAt, isNotNull);
      expect(
        DateTime.now().toUtc().difference(byId[late]!.firstSeenAt!).abs(),
        lessThan(const Duration(minutes: 5)),
      );
    });

    test(
      'a read that finds no new people opens no write transaction',
      () async {
        await addPeer('Uftnowrite01');

        await read();
        expect(await firstSeenWrites(), 1);

        await read();
        await read();
        expect(await firstSeenWrites(), 1);
      },
    );

    test('a read that finds no new people opens no write transaction, a read '
        'that records a new person opens exactly one', () async {
      const kept = 'Uftcommit001';
      await addPeer(kept);
      await addPeer('Uftcommit002');
      await read();

      // Scoped to this viewer's table: the trigger counter sees every
      // first-seen INSERT statement, i.e. every write transaction the
      // snapshot opens, and nothing from other suites or databases.
      Future<int> writesAfter(Future<void> Function() action) async {
        final before = await firstSeenWrites();
        await action();
        return (await firstSeenWrites()) - before;
      }

      // Control: one person lacks a first-seen row, so the read must write.
      await db.customStatement('''
DELETE FROM public.person_field_first_seen
WHERE viewer_id = '$viewer' AND peer_id = '$kept'
''');
      final withWrite = await writesAfter(read);
      final withoutWrite = await writesAfter(read);

      final rows = await firstSeenRows();
      expect(rows[kept], isNotNull);
      expect(rows[kept], isNot('-infinity'));
      expect(withWrite, 1);
      expect(withoutWrite, 0);
    });

    test('the snapshot stays REPEATABLE READ READ ONLY while it records '
        'first seen afterwards', () async {
      await addPeer('Uftisolate01');
      String? isolation;
      String? readOnly;
      final probing = ConstellationFieldRepository(
        db,
        _PgProfileLookup(db),
        snapshotOpenProbe: (probeDb) async {
          isolation =
              (await probeDb
                      .customSelect(
                        "SELECT current_setting('transaction_isolation') AS v",
                      )
                      .getSingle())
                  .read<String>('v');
          readOnly =
              (await probeDb
                      .customSelect(
                        "SELECT current_setting('transaction_read_only') AS v",
                      )
                      .getSingle())
                  .read<String>('v');
        },
      );

      await read(probing);

      expect(isolation, contains('repeatable read'));
      expect(readOnly, 'on');
      expect(await firstSeenRows(), {'Uftisolate01': '-infinity'});
    });
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
