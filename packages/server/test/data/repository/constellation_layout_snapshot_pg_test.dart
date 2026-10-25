@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_layout_snapshot_repository.dart';
import 'package:tentura_server/domain/entity/constellation_layout_snapshot.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

import '../../support/constellation_anchor_batch_fixture.dart';
import '../../support/disposable_pg_target.dart';

/// Saved Field layouts: a rolling history of the newest 20 snapshots, one
/// favourite per viewer, restore through the anchor write path (one realtime
/// hint, a `restore` history snapshot first) and an atomic reset that records
/// its own undo snapshot.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_LAYOUT_SNAPSHOT_TEST_DB',
    defaultNamePrefix: 'tentura_test_layoutsnap',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Ulsviewer0001';
  const otherViewer = 'Ulsviewer0002';
  const personA = 'Ulsperson0001';
  const personB = 'Ulsperson0002';
  const personNew = 'Ulsperson0003';
  const personGone = 'Ulsperson0004';

  ConstellationAnchorPosition at(double x, double y) =>
      ConstellationAnchorPosition(
        xUnits: x,
        yUnits: y,
        coordinateSpaceVersion: 1,
      );

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late ConstellationAnchorRepository anchors;
  late ConstellationLayoutSnapshotRepository snapshots;
  late Connection listener;
  late StreamSubscription<String> subscription;
  final hints = <Map<String, dynamic>>[];

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  Future<void> pin(String person, double x, double y) =>
      anchors.applyAnchorUpsert(
        viewerId: viewer,
        context: '',
        target: ConstellationAnchorTarget.person(person),
        position: at(x, y),
      );

  /// Live anchors of [viewerId] as `personId -> (x, y)`.
  Future<Map<String, (double, double)>> pinned([String? viewerId]) async {
    final rows = await db
        .customSelect(
          'SELECT person_id, x_units, y_units '
          'FROM public.constellation_anchor '
          "WHERE viewer_id = '${viewerId ?? viewer}' "
          'AND person_id IS NOT NULL',
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('person_id'): (
          r.read<double>('x_units'),
          r.read<double>('y_units'),
        ),
    };
  }

  /// Anchors stored in a snapshot as `personId -> (x, y)`.
  Future<Map<String, (double, double)>> payload(String snapshotId) async {
    final row = await db
        .customSelect(
          'SELECT anchors::text AS a '
          'FROM public.constellation_layout_snapshot '
          "WHERE id = '$snapshotId'",
        )
        .getSingle();
    final list = jsonDecode(row.read<String>('a')) as List<dynamic>;
    return {
      for (final raw in list.cast<Map<String, dynamic>>())
        if (raw['targetKind'] == 'person')
          raw['targetId'] as String: (
            (raw['x'] as num).toDouble(),
            (raw['y'] as num).toDouble(),
          ),
    };
  }

  Future<void> failSnapshotInserts() async {
    await db.customStatement(r'''
CREATE OR REPLACE FUNCTION public.fail_snapshot_insert() RETURNS trigger
LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'forced snapshot failure'; END $$
''');
    await db.customStatement('''
CREATE TRIGGER fail_snapshot_insert BEFORE INSERT
ON public.constellation_layout_snapshot
FOR EACH ROW EXECUTE FUNCTION public.fail_snapshot_insert()
''');
  }

  /// Stored kind: 0 = the single favourite, 1 = rolling history.
  Future<int> snapshotCount(int kind) async =>
      (await db
              .customSelect(
                'SELECT count(*)::int AS c '
                'FROM public.constellation_layout_snapshot '
                "WHERE viewer_id = '$viewer' AND kind = $kind",
              )
              .getSingle())
          .read<int>('c');

  Future<ConstellationLayoutSnapshot> saveHistory(String opId) =>
      snapshots.save(
        viewerId: viewer,
        kind: ConstellationLayoutSnapshotKind.history,
        reason: ConstellationLayoutSnapshotReason.manual,
        clientOpId: opId,
      );

  Future<ConstellationLayoutSnapshot> saveFavourite(String opId) =>
      snapshots.save(
        viewerId: viewer,
        kind: ConstellationLayoutSnapshotKind.favourite,
        reason: ConstellationLayoutSnapshotReason.manual,
        clientOpId: opId,
      );

  Future<void> restore(String snapshotId, String opId, {String? as}) =>
      snapshots.restore(
        viewerId: as ?? viewer,
        snapshotId: snapshotId,
        clientOpId: opId,
      );

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    db = openDisposablePgDatabase(target);
    anchors = constellationAnchorRepositoryFor(db);
    snapshots = ConstellationLayoutSnapshotRepository(db);
    listener = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    await listener.execute('LISTEN entity_changes');
    subscription = listener.channels['entity_changes'].listen((payload) {
      final message = jsonDecode(payload) as Map<String, dynamic>;
      if (message['entity'] == 'constellation_anchor') hints.add(message);
    });
  });

  tearDownAll(() async {
    await subscription.cancel();
    await listener.close();
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  setUp(() async {
    await db.customStatement(
      'DROP TRIGGER IF EXISTS fail_snapshot_insert '
      'ON public.constellation_layout_snapshot',
    );
    await db.customStatement(
      'TRUNCATE public.constellation_layout_snapshot, '
      'public.constellation_anchor, public.constellation_anchor_cursor, '
      'public.constellation_anchor_op_log, '
      'public.constellation_anchor_target_watermark CASCADE',
    );
    for (final id in [
      viewer,
      otherViewer,
      personA,
      personB,
      personNew,
      personGone,
    ]) {
      await db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT (id) DO NOTHING
''');
    }
    await pin(personA, 1, 1);
    await pin(personB, 2, 2);
    await settle();
    hints.clear();
  });

  group('saving and listing', () {
    test('a saved snapshot lists with the anchors it captured', () async {
      final saved = await saveHistory('save-1');

      expect(saved.anchorCount, 2);
      final listed = await snapshots.list(viewer);
      expect(listed.map((s) => s.id), [saved.id]);
      expect(listed.single.kind, ConstellationLayoutSnapshotKind.history);
      expect(listed.single.anchorCount, 2);
      expect(await payload(saved.id), {
        personA: (1.0, 1.0),
        personB: (2.0, 2.0),
      });
    });

    test('list returns saved coordinates only to their viewer', () async {
      await pin(personA, -3.25, 4.5);
      final saved = await saveHistory('read-anchors');
      await pin(personA, 9, 9);

      final listed = (await snapshots.list(viewer)).single;
      expect(listed.id, saved.id);
      expect(
        {
          for (final a in listed.anchors)
            a.targetId: (a.targetKind, a.x, a.y, a.coordinateSpaceVersion),
        },
        {
          personA: (ConstellationAnchorTargetKind.person, -3.25, 4.5, 1),
          personB: (ConstellationAnchorTargetKind.person, 2.0, 2.0, 1),
        },
      );
      expect(await snapshots.list(otherViewer), isEmpty);
    });

    test(
      'favourite undo restores only the favourite and replays safely',
      () async {
        final previous = await saveFavourite('fav-before');
        for (var i = 0; i < 20; i++) {
          await saveHistory('between-favourites-$i');
        }
        await pin(personA, 6, 7);
        await saveFavourite('fav-after');
        await snapshots.restoreFavourite(
          viewerId: viewer,
          snapshotId: previous.id,
          clientOpId: 'fav-undo',
        );
        final favourite = (await snapshots.list(viewer)).singleWhere(
          (s) => s.kind == ConstellationLayoutSnapshotKind.favourite,
        );
        expect(await payload(favourite.id), {
          personA: (1.0, 1.0),
          personB: (2.0, 2.0),
        });
        expect((await pinned())[personA], (6.0, 7.0));
        await snapshots.restoreFavourite(
          viewerId: viewer,
          snapshotId: '',
          clientOpId: 'fav-clear',
        );
        final newer = await saveFavourite('fav-newer');
        await snapshots.restoreFavourite(
          viewerId: viewer,
          snapshotId: '',
          clientOpId: 'fav-clear',
        );
        expect(
          (await snapshots.list(viewer))
              .singleWhere(
                (s) => s.kind == ConstellationLayoutSnapshotKind.favourite,
              )
              .id,
          newer.id,
        );
        await expectLater(
          snapshots.restoreFavourite(
            viewerId: otherViewer,
            snapshotId: previous.id,
            clientOpId: 'foreign-fav',
          ),
          throwsA(isA<PeopleTagsException>()),
        );
      },
    );

    test('the 21st history snapshot drops the oldest', () async {
      final ids = <String>[];
      for (var i = 0; i < 21; i++) {
        ids.add((await saveHistory('save-$i')).id);
      }

      final listed = (await snapshots.list(viewer))
          .where((s) => s.kind == ConstellationLayoutSnapshotKind.history)
          .map((s) => s.id)
          .toSet();
      expect(listed, hasLength(20));
      expect(listed, isNot(contains(ids.first)));
      expect(listed, contains(ids.last));
    });

    test(
      'a viewer keeps one favourite; saving another overwrites it',
      () async {
        await saveFavourite('fav-1');
        await pin(personA, 5, 5);
        final second = await saveFavourite('fav-2');

        expect(await snapshotCount(0), 1);
        final favourites = (await snapshots.list(viewer)).where(
          (s) => s.kind == ConstellationLayoutSnapshotKind.favourite,
        );
        expect(favourites.map((s) => s.id), [second.id]);
        expect((await payload(second.id))[personA], (5.0, 5.0));
      },
    );

    test(
      'a history save replayed by operation id saves nothing twice',
      () async {
        final first = await saveHistory('save-replay');
        final retry = await saveHistory('save-replay');

        expect(retry.id, first.id);
        expect(await snapshotCount(1), 1);
      },
    );

    test('a favourite save replayed by operation id changes nothing', () async {
      final first = await saveFavourite('fav-replay');
      await pin(personA, 5, 5);
      final retry = await saveFavourite('fav-replay');

      expect(retry.id, first.id);
      expect(await snapshotCount(0), 1);
      expect((await payload(first.id))[personA], (1.0, 1.0));
    });
  });

  group('restoring', () {
    test(
      'present targets equal the snapshot; newer people are unpinned',
      () async {
        final saved = await saveHistory('save-1');
        await pin(personA, 9, 9);
        await pin(personNew, 7, 7);

        await restore(saved.id, 'restore-1');

        expect(await pinned(), {personA: (1.0, 1.0), personB: (2.0, 2.0)});
      },
    );

    test('a person who no longer exists keeps the stored position', () async {
      await pin(personGone, 4, 4);
      final saved = await saveHistory('save-1');
      await pin(personGone, 6, 6);
      await pin(personA, 9, 9);
      await db.customStatement(
        "DELETE FROM public.\"user\" WHERE id = '$personGone'",
      );

      await restore(saved.id, 'restore-1');

      // Present targets follow the snapshot; the absent person's stored
      // position is neither dropped nor overwritten from the snapshot, so it
      // is still there when they return.
      expect((await pinned())[personA], (1.0, 1.0));
      Future<int> rowsAt(int x) async =>
          (await db
                  .customSelect(
                    'SELECT count(*)::int AS c FROM public.constellation_anchor '
                    "WHERE viewer_id = '$viewer' AND x_units = $x AND y_units = $x",
                  )
                  .getSingle())
              .read<int>('c');
      expect(await rowsAt(6), 1);
      expect(await rowsAt(4), 0);
    });

    test(
      'writes a restore snapshot of the pre-restore layout and one hint',
      () async {
        final saved = await saveHistory('save-1');
        await pin(personA, 9, 9);
        await settle();
        hints.clear();

        await restore(saved.id, 'restore-1');
        await settle();

        final restoreSnapshots = (await snapshots.list(viewer)).where(
          (s) => s.reason == ConstellationLayoutSnapshotReason.restore,
        );
        expect(restoreSnapshots, hasLength(1));
        expect(restoreSnapshots.single.anchorCount, 2);
        expect(await payload(restoreSnapshots.single.id), {
          personA: (9.0, 9.0),
          personB: (2.0, 2.0),
        });
        expect(hints.where((h) => h['id'] == viewer), hasLength(1));
      },
    );

    test('a failing snapshot insert leaves the anchors untouched', () async {
      final saved = await saveHistory('save-1');
      await pin(personA, 9, 9);
      await failSnapshotInserts();

      await expectLater(restore(saved.id, 'restore-1'), throwsA(anything));

      expect(await pinned(), {personA: (9.0, 9.0), personB: (2.0, 2.0)});
    });

    test('a retry with the same operation id restores once', () async {
      final saved = await saveHistory('save-1');
      await pin(personA, 9, 9);
      await restore(saved.id, 'restore-1');
      final count = await snapshotCount(1);
      await pin(personA, 8, 8);

      await restore(saved.id, 'restore-1');

      expect(await snapshotCount(1), count);
      expect((await pinned())[personA], (8.0, 8.0));
    });

    test("another viewer's snapshot id is not found", () async {
      final saved = await saveHistory('save-1');

      await expectLater(
        restore(saved.id, 'restore-x', as: otherViewer),
        throwsA(
          isA<PeopleTagsException>().having(
            (e) => e.peopleTagsCode,
            'peopleTagsCode',
            PeopleTagsExceptionCode.snapshotNotFound,
          ),
        ),
      );
      expect(await pinned(otherViewer), isEmpty);
    });
  });

  group('reset with history', () {
    test(
      'writes exactly one reset snapshot of the layout it cleared',
      () async {
        await anchors.resetAll(
          viewerId: viewer,
          clientOpId: 'reset-1',
          saveHistory: true,
        );

        final listed = await snapshots.list(viewer);
        expect(listed, hasLength(1));
        expect(listed.single.reason, ConstellationLayoutSnapshotReason.reset);
        expect(listed.single.anchorCount, 2);
        expect(await payload(listed.single.id), {
          personA: (1.0, 1.0),
          personB: (2.0, 2.0),
        });
        expect(await pinned(), isEmpty);
      },
    );

    test('a retry does not write a second snapshot', () async {
      for (var i = 0; i < 2; i++) {
        await anchors.resetAll(
          viewerId: viewer,
          clientOpId: 'reset-1',
          saveHistory: true,
        );
      }

      expect(await snapshots.list(viewer), hasLength(1));
    });

    test('a failing snapshot insert leaves the anchors untouched', () async {
      await failSnapshotInserts();

      await expectLater(
        anchors.resetAll(
          viewerId: viewer,
          clientOpId: 'reset-1',
          saveHistory: true,
        ),
        throwsA(anything),
      );

      expect(await pinned(), {personA: (1.0, 1.0), personB: (2.0, 2.0)});
    });
  });
}
