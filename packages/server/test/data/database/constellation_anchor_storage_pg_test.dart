@Tags(['pg', 'mr'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/read_snapshot_unit_of_work.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_anchor_batch_fixture.dart';
import '../../support/constellation_anchor_tombstone_fixture.dart';
import '../../support/disposable_pg_target.dart';

void _expectRetainedPinPlacement(
  Result original,
  Result remaining,
  ConstellationAnchorTarget target,
) {
  final before =
      jsonDecode(original.single.single! as String) as Map<String, dynamic>;
  final after =
      jsonDecode(remaining.single.single! as String) as Map<String, dynamic>;
  expectRetainedPinTombstone(after, before, target);
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_ANCHOR_TEST_DB',
    defaultNamePrefix: 'tentura_test_ca_anchor',
  );
  final skipReason = await pgSkipReason(target);

  group('constellation anchor storage', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    final notifications = <Map<String, dynamic>>[];

    late TenturaDb db;
    late ConstellationAnchorRepository repository;
    late ReadSnapshotUnitOfWork readSnapshots;

    const viewerA = 'Ucaanchorview01';
    const viewerB = 'Ucaanchorview02';
    const personP = 'Ucaanchorpers01';
    const personQ = 'Ucaanchorpers02';
    const beaconB = 'Bcaanchorbeac01';

    Future<void> seedUser(String id) => writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

    Future<void> reciprocalTrust(String a, String b) => writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$a', '$b', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$b', '$a', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

    Future<void> seedBeacon(String id, String authorId) => writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$id', '$authorId', 't', 'd', 0, true,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
''');

    ConstellationAnchorPosition pos(double x, double y) =>
        ConstellationAnchorPosition(
          xUnits: x,
          yUnits: y,
          coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
        );

    List<Map<String, dynamic>> anchorNotifications() => notifications
        .where((m) => m['entity'] == 'constellation_anchor')
        .toList();

    /// Drop setup notifications, but only once delivery has gone quiet.
    ///
    /// `notifications.clear()` discards what has already arrived; it cannot
    /// flush what Postgres has not yet sent. A setup upsert whose notification
    /// is still in flight therefore lands *after* the clear and pollutes the
    /// test body's assertions. Wait for the first anchor notification, then
    /// for a full quiet interval with no new arrivals — an upsert can emit
    /// more than one row event — and only then clear.
    Future<void> clearAfterDelivery() async {
      await _waitUntil(() => anchorNotifications().isNotEmpty);
      var seen = anchorNotifications().length;
      while (true) {
        await _settle();
        final now = anchorNotifications().length;
        if (now == seen) break;
        seen = now;
      }
      notifications.clear();
    }

    setUpAll(() async {
      if (skipReason != null) {
        return;
      }
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      final dbName = await writer.execute('SELECT current_database()');
      expect(dbName.single.single, target.databaseName);

      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        (payload) => notifications.add(
          jsonDecode(payload) as Map<String, dynamic>,
        ),
      );
      await _settle();
      notifications.clear();

      db = openDisposablePgDatabase(target);
      repository = constellationAnchorRepositoryFor(db);
      readSnapshots = ReadSnapshotUnitOfWork(db);

      for (final id in [viewerA, viewerB, personP, personQ]) {
        await seedUser(id);
      }
      await seedBeacon(beaconB, personP);
      await reciprocalTrust(viewerA, personP);
      await reciprocalTrust(viewerA, personQ);
      await reciprocalTrust(viewerB, personP);
      await reciprocalTrust(viewerB, personQ);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE public.constellation_anchor, public.constellation_anchor_cursor CASCADE
''');
      for (final id in [viewerA, viewerB, personP, personQ]) {
        await seedUser(id);
      }
      await seedBeacon(beaconB, personP);
      // Cascade-delete tests remove users (and vote_user). Restore C2 upsert auth.
      await reciprocalTrust(viewerA, personP);
      await reciprocalTrust(viewerA, personQ);
      await reciprocalTrust(viewerB, personP);
      await reciprocalTrust(viewerB, personQ);
      notifications.clear();
    });

    tearDownAll(() async {
      if (skipReason != null) {
        return;
      }
      await notificationSubscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    test('coordinate CHECK rejects NaN and both infinities per axis', () async {
      await seedUser(viewerA);
      for (final bad in [
        ("'NaN'::float8", '0'),
        ("'Infinity'::float8", '0'),
        ("'-Infinity'::float8", '0'),
        ('0', "'NaN'::float8"),
        ('0', "'Infinity'::float8"),
        ('0', "'-Infinity'::float8"),
      ]) {
        await expectLater(
          writer.execute('''
INSERT INTO public.constellation_anchor (
  id, viewer_id, person_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (
  'CAcheck01', '$viewerA', '$personP', ${bad.$1}, ${bad.$2},
  1, 1, now()
)
'''),
          throwsA(isA<ServerException>()),
        );
      }
    });

    test('coordinate CHECK accepts envelope boundaries', () async {
      await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES ('$viewerA')
''');
      final fixtures = [
        (personP, -10.0, -10.0, 'CAedge01'),
        (personQ, 10.0, 10.0, 'CAedge02'),
        (beaconB, 0.0, 0.0, 'CAedge03'),
      ];
      for (final fixture in fixtures) {
        final personCol = fixture.$1 == beaconB ? 'NULL' : "'${fixture.$1}'";
        final beaconCol = fixture.$1 == beaconB ? "'$beaconB'" : 'NULL';
        await writer.execute('''
INSERT INTO public.constellation_anchor (
  id, viewer_id, person_id, beacon_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (
  '${fixture.$4}', '$viewerA', $personCol, $beaconCol,
  ${fixture.$2}, ${fixture.$3}, 1, 1, now()
)
''');
      }
      final count = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor WHERE viewer_id = '$viewerA'
''');
      expect(count.single.single, 3);
    });

    test(
      'partial unique indexes enforce one anchor per viewer target',
      () async {
        await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES ('$viewerA')
''');
        await writer.execute('''
INSERT INTO public.constellation_anchor (
  id, viewer_id, person_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (
  'CAuniq01', '$viewerA', '$personP', 1, 1, 1, 1, now()
)
''');
        await expectLater(
          writer.execute('''
INSERT INTO public.constellation_anchor (
  id, viewer_id, person_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (
  'CAuniq02', '$viewerA', '$personP', 2, 2, 1, 2, now()
)
'''),
          throwsA(isA<ServerException>()),
        );
      },
    );

    test('owner isolation: viewers do not share anchor rows', () async {
      final p = pos(1, 1);
      await repository.applyAnchorUpsert(
        viewerId: viewerA,
        context: kConstellationContext,
        target: ConstellationAnchorTarget.person(personP),
        position: p,
      );
      await repository.applyAnchorUpsert(
        viewerId: viewerB,
        context: kConstellationContext,
        target: ConstellationAnchorTarget.person(personP),
        position: pos(2, 2),
      );
      final rows = await writer.execute('''
SELECT viewer_id, x_units FROM public.constellation_anchor
WHERE person_id = '$personP' ORDER BY viewer_id
''');
      expect(rows.length, 2);
      expect(rows.first[0], viewerA);
      expect(rows.last[0], viewerB);
    });

    test(
      'upsert move preserves anchor id and bumps account revision monotonically',
      () async {
        await repository.applyAnchorUpsert(
          viewerId: viewerA,
          context: kConstellationContext,
          target: ConstellationAnchorTarget.person(personP),
          position: pos(1, 1),
        );
        final idAfterInsert = await writer.execute('''
SELECT id FROM public.constellation_anchor
WHERE viewer_id = '$viewerA' AND person_id = '$personP'
''');
        final anchorId = idAfterInsert.single.single as String;
        notifications.clear();
        final second = await repository.applyAnchorUpsert(
          viewerId: viewerA,
          context: kConstellationContext,
          target: ConstellationAnchorTarget.person(personP),
          position: pos(3, 3),
        );
        expect(second.anchor.revision.value, greaterThan(BigInt.zero));
        expect(second.watermark.revision.value, second.anchor.revision.value);
        final idRows = await writer.execute('''
SELECT id FROM public.constellation_anchor
WHERE viewer_id = '$viewerA' AND person_id = '$personP'
''');
        expect(idRows.single.single, anchorId);
        final countRows = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor
WHERE viewer_id = '$viewerA' AND person_id = '$personP'
''');
        expect(countRows.single.single, 1);
      },
    );

    test('placed_at is strictly increasing across rapid moves', () async {
      final a = await repository.applyAnchorUpsert(
        viewerId: viewerA,
        context: kConstellationContext,
        target: ConstellationAnchorTarget.person(personP),
        position: pos(1, 1),
      );
      final b = await repository.applyAnchorUpsert(
        viewerId: viewerA,
        context: kConstellationContext,
        target: ConstellationAnchorTarget.person(personQ),
        position: pos(2, 2),
      );
      final c = await repository.applyAnchorUpsert(
        viewerId: viewerA,
        context: kConstellationContext,
        target: ConstellationAnchorTarget.person(personP),
        position: pos(1.5, 1.5),
      );
      expect(b.anchor.placedAt.isAfter(a.anchor.placedAt), isTrue);
      expect(c.anchor.placedAt.isAfter(b.anchor.placedAt), isTrue);
      expect(c.anchor.placedAt.isAfter(a.anchor.placedAt), isTrue);
    });

    test(
      'delete existing row emits one canonical update notification',
      () async {
        await repository.applyAnchorUpsert(
          viewerId: viewerA,
          context: kConstellationContext,
          target: ConstellationAnchorTarget.person(personP),
          position: pos(1, 1),
        );
        await clearAfterDelivery();
        await repository.applyAnchorDelete(
          viewerId: viewerA,
          target: ConstellationAnchorTarget.person(personP),
        );
        await _waitUntil(() => anchorNotifications().isNotEmpty);
        expect(anchorNotifications().length, 1);
        expect(anchorNotifications().single['event'], 'update');
        expect(anchorNotifications().single['id'], viewerA);
        expect(anchorNotifications().single['user_ids'], [viewerA]);
      },
    );

    test(
      'absent-key delete increments cursor once and emits one update',
      () async {
        final before = await repository.readWatermark(viewerA);
        expect(before.value, BigInt.zero);
        notifications.clear();
        final result = await repository.applyAnchorDelete(
          viewerId: viewerA,
          target: ConstellationAnchorTarget.person(personP),
        );
        expect(result.watermark.revision.value, BigInt.one);
        await _waitUntil(() => anchorNotifications().isNotEmpty);
        expect(anchorNotifications().length, 1);
        final rows = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor WHERE viewer_id = '$viewerA'
''');
        expect(rows.single.single, 0);
      },
    );

    test(
      'aborted transaction emits no notification and rolls back cursor',
      () async {
        await repository.applyAnchorUpsert(
          viewerId: viewerA,
          context: kConstellationContext,
          target: ConstellationAnchorTarget.person(personP),
          position: pos(1, 1),
        );
        await clearAfterDelivery();
        await expectLater(
          db.withMutatingUser(viewerA, () async {
            await db.customStatement(
              '''
INSERT INTO public.constellation_anchor_cursor (viewer_id)
VALUES (\$1) ON CONFLICT DO NOTHING
''',
              [viewerA],
            );
            await db.customStatement(
              '''
SELECT viewer_id FROM public.constellation_anchor_cursor
WHERE viewer_id = \$1 FOR UPDATE
''',
              [viewerA],
            );
            await db.customStatement(
              '''
UPDATE public.constellation_anchor
SET x_units = 9 WHERE viewer_id = \$1 AND person_id = \$2
''',
              [viewerA, personP],
            );
            throw StateError('abort');
          }),
          throwsA(isA<StateError>()),
        );
        await _settle();
        expect(anchorNotifications(), isEmpty);
        final coord = await writer.execute('''
SELECT x_units::float8 FROM public.constellation_anchor
WHERE viewer_id = '$viewerA' AND person_id = '$personP'
''');
        expect(coord.single.single, 1.0);
      },
    );

    // Pins belong to their viewer (D15): deleting the target now preserves a
    // tombstone instead of silently cascading away the viewer's placement.
    test(
      'deleting a pinned Request preserves its placement as a tombstone',
      () async {
        await repository.applyAnchorUpsert(
          viewerId: viewerA,
          context: kConstellationContext,
          target: ConstellationAnchorTarget.beacon(beaconB),
          position: pos(1, 1),
        );
        final revBefore = await repository.readWatermark(viewerA);
        final original = await writer.execute('''
SELECT to_jsonb(a)::text FROM public.constellation_anchor a WHERE viewer_id = '$viewerA'
''');
        await clearAfterDelivery();
        await writer.execute("DELETE FROM public.beacon WHERE id = '$beaconB'");
        await _settle();
        final remaining = await writer.execute('''
SELECT to_jsonb(a)::text FROM public.constellation_anchor a WHERE viewer_id = '$viewerA'
''');
        expect(remaining, hasLength(1));
        _expectRetainedPinPlacement(
          original,
          remaining,
          ConstellationAnchorTarget.beacon(beaconB),
        );
        final revAfter = await repository.readWatermark(viewerA);
        expect(revAfter.value, revBefore.value + BigInt.one);
        expect(anchorNotifications().length, 1);
        expect(anchorNotifications().single['event'], 'update');
        expect(
          anchorNotifications().single['revision'],
          revAfter.toDecimalString(),
        );
      },
    );

    test(
      'deleting a pinned person preserves its placement as a tombstone',
      () async {
        await repository.applyAnchorUpsert(
          viewerId: viewerA,
          context: kConstellationContext,
          target: ConstellationAnchorTarget.person(personQ),
          position: pos(1, 1),
        );
        final revBefore = await repository.readWatermark(viewerA);
        final original = await writer.execute('''
SELECT to_jsonb(a)::text FROM public.constellation_anchor a WHERE viewer_id = '$viewerA'
''');
        await clearAfterDelivery();
        await writer.execute(
          "DELETE FROM public.\"user\" WHERE id = '$personQ'",
        );
        await _settle();
        final remaining = await writer.execute('''
SELECT to_jsonb(a)::text FROM public.constellation_anchor a WHERE viewer_id = '$viewerA'
''');
        expect(remaining, hasLength(1));
        _expectRetainedPinPlacement(
          original,
          remaining,
          ConstellationAnchorTarget.person(personQ),
        );
        final revAfter = await repository.readWatermark(viewerA);
        expect(revAfter.value, revBefore.value + BigInt.one);
        expect(anchorNotifications(), hasLength(1));
        expect(anchorNotifications().single['event'], 'update');
        expect(
          anchorNotifications().single['revision'],
          revAfter.toDecimalString(),
        );
      },
    );

    test('viewer delete removes cursor and anchors without recreate', () async {
      await repository.applyAnchorUpsert(
        viewerId: viewerB,
        context: kConstellationContext,
        target: ConstellationAnchorTarget.person(personP),
        position: pos(1, 1),
      );
      await writer.execute(
        "DELETE FROM public.\"user\" WHERE id = '$viewerB'",
      );
      final cursor = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor_cursor
''');
      expect(cursor.single.single, 0);
      final anchors = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor WHERE viewer_id = '$viewerB'
''');
      expect(anchors.single.single, 0);
    });

    test(
      'anchor row delete with cursor already removed emits no notification',
      () async {
        await repository.applyAnchorUpsert(
          viewerId: viewerA,
          context: kConstellationContext,
          target: ConstellationAnchorTarget.person(personP),
          position: pos(1, 1),
        );
        await clearAfterDelivery();
        await writer.execute('''
DELETE FROM public.constellation_anchor_cursor WHERE viewer_id = '$viewerA'
''');
        await writer.execute('''
DELETE FROM public.constellation_anchor
WHERE viewer_id = '$viewerA' AND person_id = '$personP'
''');
        await _settle();
        expect(anchorNotifications(), isEmpty);
      },
    );

    test(
      'person and beacon anchors each emit one update notification on row cascade',
      () async {
        const extraBeacon = 'Bcaanchorbeac02';
        await seedBeacon(extraBeacon, personQ);
        await repository.applyAnchorUpsert(
          viewerId: viewerA,
          context: kConstellationContext,
          target: ConstellationAnchorTarget.person(personP),
          position: pos(1, 1),
        );
        await repository.applyAnchorUpsert(
          viewerId: viewerA,
          context: kConstellationContext,
          target: ConstellationAnchorTarget.beacon(extraBeacon),
          position: pos(2, 2),
        );
        // Wait for the two upsert notifications to be delivered before
        // clearing: clear() does not flush what Postgres has not yet sent, so
        // under load a late upsert lands after the clear and fails the
        // every(event == 'update') assertion below.
        await _waitUntil(() => anchorNotifications().length >= 2);
        notifications.clear();
        await writer.execute('''
DELETE FROM public.constellation_anchor
WHERE viewer_id = '$viewerA' AND person_id = '$personP'
''');
        await writer.execute('''
DELETE FROM public.constellation_anchor
WHERE viewer_id = '$viewerA' AND beacon_id = '$extraBeacon'
''');
        await _waitUntil(() => anchorNotifications().length >= 2);
        expect(
          anchorNotifications().every((m) => m['event'] == 'update'),
          isTrue,
        );
        expect(
          anchorNotifications().every((m) => m['id'] == viewerA),
          isTrue,
        );
      },
    );

    test(
      'withReadSnapshot uses repeatable read readonly transaction',
      () async {
        String? isolation;
        String? readOnly;
        await readSnapshots.withReadSnapshot(() async {
          final iso = await db
              .customSelect(
                "SELECT current_setting('transaction_isolation') AS v",
              )
              .getSingle();
          final ro = await db
              .customSelect(
                "SELECT current_setting('transaction_read_only') AS v",
              )
              .getSingle();
          isolation = iso.read<String>('v');
          readOnly = ro.read<String>('v');
          return null;
        });
        expect(isolation, contains('repeatable read'));
        expect(readOnly, 'on');
      },
    );

    test('readWatermark returns zero without creating cursor row', () async {
      final watermark = await readSnapshots.withReadSnapshot(
        () => repository.readWatermark(viewerA),
      );
      expect(watermark.value, BigInt.zero);
      final rows = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor_cursor WHERE viewer_id = '$viewerA'
''');
      expect(rows.single.single, 0);
    });

    test(
      'readonly visibility cache miss does not write cache rows',
      () async {
        await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewerA', '$personP', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$personP', '$viewerA', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING
''');
        await writer.execute(
          "SELECT mr_put_edge('$viewerA', '$personP', 0.75::double precision, ''::text, 0)",
        );
        await writer.execute(
          'TRUNCATE public.person_mutual_visibility_cache',
        );
        final before = await writer.execute(
          'SELECT count(*)::int FROM public.person_mutual_visibility_cache',
        );
        expect(before.single.single, 0);

        final conn = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        try {
          await conn.execute('BEGIN');
          await conn.execute(
            'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY',
          );
          final mutual = await conn.execute(
            Sql.named(
              r'''
SELECT public.person_are_mutually_visible_cached(@a, @b, @ctx) AS mutual
''',
            ),
            parameters: {'a': viewerA, 'b': personP, 'ctx': ''},
          );
          expect(mutual.single.first, isTrue);
          final mid = await conn.execute(
            'SELECT count(*)::int FROM public.person_mutual_visibility_cache',
          );
          expect(mid.single.single, 0);
          await conn.execute('COMMIT');
        } finally {
          await conn.close();
        }
      },
    );
  }, skip: skipReason);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (!condition()) {
    if (DateTime.timestamp().isAfter(deadline)) {
      fail('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
