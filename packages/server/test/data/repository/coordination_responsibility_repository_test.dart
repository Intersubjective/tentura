@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/domain/entity/coordination_responsibility_counts.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

/// Postgres integration — skipped when DB or m0090 schema is unavailable.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final env = _testEnv();
    final probe = TenturaDb(env);
    try {
      if (!await _hasResponsibilitySchema(probe)) {
        skipReason = 'm0090 schema (beacon_items_seen / published_at) missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late CoordinationItemRepository repo;

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      repo = CoordinationItemRepository(db);
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.coordination_item WHERE id LIKE 'Iresptest%'",
      );
      if (await _hasBeaconItemsSeenTable(db)) {
        await db.customStatement(
          "DELETE FROM public.beacon_items_seen WHERE beacon_id LIKE 'Bresptest%'",
        );
      }
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id LIKE 'Bresptest%'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ('Uresptestview1', 'Uresptestauth1')''',
      );
    });
  }

  Future<void> seedFixture() async {
    final viewerKey = pgTestPublicKey('resptest', 1);
    final authorKey = pgTestPublicKey('resptest', 2);
    await db.customStatement(
      r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('Uresptestview1', 'Viewer One', $1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Uresptestauth1', 'Author One', $2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key
''',
      [viewerKey, authorKey],
    );
    await db.customStatement(
      '''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES ('Bresptestbcn1', 'Uresptestauth1', 'Responsibility test', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
    );
    await db.customStatement(
      '''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id, target_person_id,
  target_item_id, published, created_at, updated_at, published_at, source, ordering
) VALUES
  ('Iresptestask01', 'Bresptestbcn1', 2, 0, 'Ask me', '', 'Uresptestauth1', 'Uresptestview1', NULL, true,
   '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 0, 0),
  ('Iresptestprom01', 'Bresptestbcn1', 5, 0, 'My promise', '', 'Uresptestview1', 'Uresptestauth1', NULL, true,
   '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z', '2026-01-04T00:00:00Z', 0, 0),
  ('Iresptestblk01', 'Bresptestbcn1', 3, 0, 'Blocker', '', 'Uresptestauth1', 'Uresptestview1', NULL, true,
   '2026-01-03T00:00:00Z', '2026-01-03T00:00:00Z', '2026-01-03T00:00:00Z', 0, 0),
  ('Iresptestrev01', 'Bresptestbcn1', 4, 0, 'Review', '', 'Uresptestauth1', NULL, 'Iresptestask01', true,
   '2026-01-04T00:00:00Z', '2026-01-04T00:00:00Z', '2026-01-04T00:00:00Z', 0, 0),
  ('Iresptestoth01', 'Bresptestbcn1', 2, 0, 'Ask author', '', 'Uresptestview1', 'Uresptestauth1', NULL, true,
   '2026-01-05T00:00:00Z', '2026-01-05T00:00:00Z', '2026-01-05T00:00:00Z', 0, 0),
  ('Iresptestdrft1', 'Bresptestbcn1', 2, 0, 'Draft', '', 'Uresptestauth1', 'Uresptestview1', NULL, false,
   '2026-01-06T00:00:00Z', '2026-01-06T00:00:00Z', NULL, 0, 0),
  ('Iresptestres01', 'Bresptestbcn1', 2, 2, 'Resolved ask', '', 'Uresptestauth1', 'Uresptestview1', NULL, true,
   '2026-01-07T00:00:00Z', '2026-01-07T00:00:00Z', '2026-01-07T00:00:00Z', 0, 0)
ON CONFLICT (id) DO NOTHING
''',
    );
  }

  int personalOpenTotal(CoordinationResponsibilityCounts row) =>
      row.askOpen + row.promiseOpen + row.blockerOpen + row.reviewOpen;

  test(
    'batch open/new counts match myResponsibilityItemsByBeacon per kind',
    () async {
      await seedFixture();
      const viewerId = 'Uresptestview1';
      const beaconId = 'Bresptestbcn1';

      final counts = await repo.responsibilityCountsByBeaconIds(
        viewerUserId: viewerId,
        beaconIds: [beaconId],
      );
      final row = counts.single;
      final items = await repo.myResponsibilityItemsByBeacon(
        viewerUserId: viewerId,
        beaconId: beaconId,
      );

      expect(row.askOpen, 1);
      expect(row.promiseOpen, 1);
      expect(row.blockerOpen, 1);
      expect(row.reviewOpen, 1);
      expect(row.othersOpenCount, 1);

      expect(
        items.where((e) => e.item.kind == coordinationItemKindAsk).length,
        row.askOpen,
      );
      expect(
        items.where((e) => e.item.kind == coordinationItemKindPromise).length,
        row.promiseOpen,
      );
      expect(
        items.where((e) => e.item.kind == coordinationItemKindBlocker).length,
        row.blockerOpen,
      );
      expect(
        items.where((e) => e.item.kind == coordinationItemKindResolution).length,
        row.reviewOpen,
      );
      expect(items, hasLength(personalOpenTotal(row)));
    },
    skip: skipReason,
  );

  test(
    'excludes drafts unpublished and terminal statuses from count buckets',
    () async {
      await seedFixture();
      const viewerId = 'Uresptestview1';
      const beaconId = 'Bresptestbcn1';

      final before = await repo.responsibilityCountsByBeaconIds(
        viewerUserId: viewerId,
        beaconIds: [beaconId],
      );
      final baseline = before.single;

      await db.customStatement(
        '''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id, target_person_id,
  target_item_id, published, created_at, updated_at, published_at, source, ordering
) VALUES
  ('Iresptestcncl1', 'Bresptestbcn1', 2, 3, 'Cancelled ask', '', 'Uresptestauth1', 'Uresptestview1', NULL, true,
   '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', 0, 0),
  ('Iresptestsupr1', 'Bresptestbcn1', 5, 4, 'Superseded promise', '', 'Uresptestview1', 'Uresptestauth1', NULL, true,
   '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', 0, 0),
  ('Iresptestunpub', 'Bresptestbcn1', 2, 0, 'Unpublished ask', '', 'Uresptestauth1', 'Uresptestview1', NULL, false,
   '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', NULL, 0, 0)
ON CONFLICT (id) DO NOTHING
''',
      );

      final after = await repo.responsibilityCountsByBeaconIds(
        viewerUserId: viewerId,
        beaconIds: [beaconId],
      );
      final row = after.single;

      expect(row.askOpen, baseline.askOpen);
      expect(row.promiseOpen, baseline.promiseOpen);
      expect(row.blockerOpen, baseline.blockerOpen);
      expect(row.reviewOpen, baseline.reviewOpen);
      expect(row.othersOpenCount, baseline.othersOpenCount);
    },
    skip: skipReason,
  );

  test(
    'accepted status items still count as open responsibility',
    () async {
      await seedFixture();
      const viewerId = 'Uresptestview1';
      const beaconId = 'Bresptestbcn1';

      await db.customStatement(
        '''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id, target_person_id,
  target_item_id, published, created_at, updated_at, published_at, source, ordering
) VALUES
  ('Iresptestacc01', 'Bresptestbcn1', 2, 1, 'Accepted ask', '', 'Uresptestauth1', 'Uresptestview1', NULL, true,
   '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', 0, 0)
ON CONFLICT (id) DO NOTHING
''',
      );

      final counts = await repo.responsibilityCountsByBeaconIds(
        viewerUserId: viewerId,
        beaconIds: [beaconId],
      );
      final items = await repo.myResponsibilityItemsByBeacon(
        viewerUserId: viewerId,
        beaconId: beaconId,
      );
      final row = counts.single;

      expect(row.askOpen, 2);
      expect(items.any((e) => e.item.id == 'Iresptestacc01'), isTrue);
    },
    skip: skipReason,
  );

  test(
    'author sees asks targeted at them and othersOpen for room activity outside responsibility',
    () async {
      await seedFixture();
      const authorId = 'Uresptestauth1';
      const beaconId = 'Bresptestbcn1';

      final counts = await repo.responsibilityCountsByBeaconIds(
        viewerUserId: authorId,
        beaconIds: [beaconId],
      );
      final row = counts.single;

      expect(row.askOpen, 1);
      expect(row.promiseOpen, 0);
      expect(row.blockerOpen, 0);
      expect(row.reviewOpen, 0);
      expect(row.othersOpenCount, 4);
    },
    skip: skipReason,
  );

  test(
    'review counts when viewer owns targeted ask promise or blocker',
    () async {
      await seedFixture();
      const viewerId = 'Uresptestview1';
      const beaconId = 'Bresptestbcn1';

      await db.customStatement(
        '''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id, target_person_id,
  target_item_id, published, created_at, updated_at, published_at, source, ordering
) VALUES
  ('Iresptestprmp2', 'Bresptestbcn1', 5, 0, 'Second promise', '', 'Uresptestview1', 'Uresptestauth1', NULL, true,
   '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', 0, 0),
  ('Iresptestblk2', 'Bresptestbcn1', 3, 0, 'Second blocker', '', 'Uresptestauth1', 'Uresptestview1', NULL, true,
   '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', 0, 0),
  ('Iresptestrevp2', 'Bresptestbcn1', 4, 0, 'Review promise', '', 'Uresptestauth1', NULL, 'Iresptestprmp2', true,
   '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', 0, 0),
  ('Iresptestrevb2', 'Bresptestbcn1', 4, 0, 'Review blocker', '', 'Uresptestauth1', NULL, 'Iresptestblk2', true,
   '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', 0, 0),
  ('Iresptestrevx1', 'Bresptestbcn1', 4, 0, 'Review unrelated', '', 'Uresptestauth1', NULL, 'Iresptestoth01', true,
   '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', '2026-01-08T00:00:00Z', 0, 0)
ON CONFLICT (id) DO NOTHING
''',
      );

      final counts = await repo.responsibilityCountsByBeaconIds(
        viewerUserId: viewerId,
        beaconIds: [beaconId],
      );
      final items = await repo.myResponsibilityItemsByBeacon(
        viewerUserId: viewerId,
        beaconId: beaconId,
      );
      final row = counts.single;

      expect(row.reviewOpen, 3);
      expect(
        items.where((e) => e.item.kind == coordinationItemKindResolution).length,
        row.reviewOpen,
      );
      expect(items.any((e) => e.item.id == 'Iresptestrevx1'), isFalse);
    },
    skip: skipReason,
  );

  test(
    'promise responsibility uses creator_id not target_person_id',
    () async {
      await seedFixture();
      const authorId = 'Uresptestauth1';
      const beaconId = 'Bresptestbcn1';

      final counts = await repo.responsibilityCountsByBeaconIds(
        viewerUserId: authorId,
        beaconIds: [beaconId],
      );
      final row = counts.single;

      expect(row.promiseOpen, 0);
      expect(row.othersOpenCount, greaterThanOrEqualTo(1));
    },
    skip: skipReason,
  );

  test(
    'batch returns zero counts for beacon with no coordination items',
    () async {
      await seedFixture();
      const viewerId = 'Uresptestview1';

      await db.customStatement(
        '''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES ('Bresptestbcn2', 'Uresptestauth1', 'Empty beacon', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      );

      final counts = await repo.responsibilityCountsByBeaconIds(
        viewerUserId: viewerId,
        beaconIds: ['Bresptestbcn1', 'Bresptestbcn2'],
      );

      expect(counts, hasLength(2));
      final empty = counts.singleWhere((r) => r.beaconId == 'Bresptestbcn2');
      expect(personalOpenTotal(empty), 0);
      expect(empty.othersOpenCount, 0);
      expect(empty.totalNew, 0);
    },
    skip: skipReason,
  );

  test(
    'empty beaconIds returns empty list',
    () async {
      final counts = await repo.responsibilityCountsByBeaconIds(
        viewerUserId: 'Uresptestview1',
        beaconIds: const [],
      );
      expect(counts, isEmpty);
    },
    skip: skipReason,
  );

  test(
    'newCount uses published_at after watermark',
    () async {
      await seedFixture();
      const viewerId = 'Uresptestview1';
      const beaconId = 'Bresptestbcn1';

      await db.customStatement(
        r'''
INSERT INTO public.beacon_items_seen (user_id, beacon_id, last_seen_at)
VALUES ($1, $2, '2026-01-03T12:00:00Z'::timestamptz)
ON CONFLICT (user_id, beacon_id) DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at
''',
        [viewerId, beaconId],
      );

      final counts = await repo.responsibilityCountsByBeaconIds(
        viewerUserId: viewerId,
        beaconIds: [beaconId],
      );
      final row = counts.single;

      expect(row.askNew, 0);
      expect(row.blockerNew, 0);
      expect(row.promiseNew, 1);
      expect(row.reviewNew, 1);
    },
    skip: skipReason,
  );

  test(
    'markBeaconItemsSeen clamps to latest responsibility published_at and is monotonic',
    () async {
      await seedFixture();
      const viewerId = 'Uresptestview1';
      const beaconId = 'Bresptestbcn1';

      final first = await repo.markBeaconItemsSeen(
        userId: viewerId,
        beaconId: beaconId,
      );
      final persisted1 = await repo.getBeaconItemsSeen(
        userId: viewerId,
        beaconId: beaconId,
      );

      expect(persisted1, isNotNull);
      expect(first, persisted1);
      expect(
        persisted1!.isAfter(DateTime.utc(2026, 1, 3)),
        isTrue,
      );

      await db.customStatement(
        r'''
INSERT INTO public.beacon_items_seen (user_id, beacon_id, last_seen_at)
VALUES ($1, $2, '2026-12-31T00:00:00Z'::timestamptz)
ON CONFLICT (user_id, beacon_id) DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at
''',
        [viewerId, beaconId],
      );

      final second = await repo.markBeaconItemsSeen(
        userId: viewerId,
        beaconId: beaconId,
      );
      final persisted2 = await repo.getBeaconItemsSeen(
        userId: viewerId,
        beaconId: beaconId,
      );

      expect(
        persisted2!.isAfter(DateTime.utc(2026, 12, 30)),
        isTrue,
      );
      expect(second, persisted2);
    },
    skip: skipReason,
  );
}

Env _testEnv() => Env(
      environment: Environment.test,
      pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
      pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
      pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
      printEnv: false,
      isDebugModeOn: false,
    );

Future<bool> _hasBeaconItemsSeenTable(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1 FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'beacon_items_seen'
LIMIT 1
''',
  ).get();
  return rows.isNotEmpty;
}

Future<bool> _hasResponsibilitySchema(TenturaDb db) async {
  final publishedAt = await db.customSelect(
    '''
SELECT 1 FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'coordination_item'
  AND column_name = 'published_at'
LIMIT 1
''',
  ).get();
  return publishedAt.isNotEmpty && await _hasBeaconItemsSeenTable(db);
}

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } on Object catch (_) {
    return false;
  }
}
