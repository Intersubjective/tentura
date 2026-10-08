@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';

import '../../support/disposable_pg_target.dart';

/// Constellation anchor realtime hints are emitted by deferred constraint
/// triggers: one canonical `update` envelope per viewer per committed
/// transaction, carrying the final cursor revision.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_ANCHOR_DEFERRED_NOTIFY_TEST_DB',
    defaultNamePrefix: 'tentura_test_cadefnotify',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('constellation anchor deferred notifications', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    late TenturaDb db;
    late ConstellationAnchorRepository repo;
    final notifications = <Map<String, dynamic>>[];

    const viewer = 'Ucadefviewer1';
    const otherViewer = 'Ucadefviewer2';
    const person = 'Ucadefpeer001';
    const beacon = 'Bcadefbeac001';
    const beaconCount = 32;
    const personCount = 32;

    String personId(int i) => 'Ucadefp${i.toString().padLeft(6, '0')}';
    String beaconId(int i) => 'Bcadefb${i.toString().padLeft(6, '0')}';

    List<Map<String, dynamic>> anchorHints([String? forViewer]) => notifications
        .where(
          (m) =>
              m['entity'] == 'constellation_anchor' &&
              (forViewer == null || m['id'] == forViewer),
        )
        .toList();

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 200));

    Future<BigInt> cursorRevision(String viewerId) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT revision FROM public.constellation_anchor_cursor '
          'WHERE viewer_id = @viewer',
        ),
        parameters: {'viewer': viewerId},
      );
      final raw = rows.single.single;
      return raw is BigInt ? raw : BigInt.from(raw! as int);
    }

    /// Number of times the strict publisher was invoked for an anchor hint
    /// by committed transactions (rolled-back calls leave no row).
    Future<int> publisherCalls([String? forViewer]) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT count(*)::int FROM public.anchor_publisher_probe '
          'WHERE @viewer::text IS NULL OR recipient = @viewer',
        ),
        parameters: {'viewer': forViewer},
      );
      return rows.single.single! as int;
    }

    Future<void> insertAnchor(
      TxSession tx, {
      required String viewerId,
      String? personTarget,
      String? beaconTarget,
      double x = 1,
    }) => tx.execute(
      Sql.named('''
INSERT INTO public.constellation_anchor
  (id, viewer_id, person_id, beacon_id, x_units, y_units,
   coordinate_space_version, revision, placed_at)
VALUES
  (@id, @viewer, @person, @beacon, @x, 0, 1, 0, now())
'''),
      parameters: {
        'id':
            'A${DateTime.now().microsecondsSinceEpoch}'
            '${personTarget ?? beaconTarget}',
        'viewer': viewerId,
        'person': personTarget,
        'beacon': beaconTarget,
        'x': x,
      },
    );

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;

      Future<void> user(String id) => writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
      Future<void> beaconRow(String id, String owner) => writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$id', '$owner', 't', 'd', 0, true,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
''');
      await user(viewer);
      await user(otherViewer);
      await user(person);
      await beaconRow(beacon, person);
      for (var i = 0; i < personCount; i++) {
        await user(personId(i));
      }
      for (var i = 0; i < beaconCount; i++) {
        await beaconRow(beaconId(i), person);
      }

      // Count strict-publisher invocations for anchor hints: wrap the real
      // publisher (triggers resolve it by name at fire time) and log calls.
      await writer.execute('''
CREATE TABLE public.anchor_publisher_probe (
  recipient text NOT NULL,
  event text NOT NULL,
  extra jsonb NOT NULL
)
''');
      await writer.execute('''
ALTER FUNCTION public.emit_realtime_entity_change_strict(
  text, text, text, text[], jsonb
) RENAME TO emit_realtime_entity_change_strict_real
''');
      await writer.execute(r'''
CREATE FUNCTION public.emit_realtime_entity_change_strict(
  p_entity text,
  p_id text,
  p_event text,
  p_user_ids text[],
  p_extra jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_entity = 'constellation_anchor' THEN
    INSERT INTO public.anchor_publisher_probe (recipient, event, extra)
    VALUES (p_id, p_event, COALESCE(p_extra, '{}'::jsonb));
  END IF;
  PERFORM public.emit_realtime_entity_change_strict_real(
    p_entity, p_id, p_event, p_user_ids, p_extra
  );
END;
$$
''');

      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        (payload) =>
            notifications.add(jsonDecode(payload) as Map<String, dynamic>),
      );
      await settle();

      db = TenturaDb(target.databaseEnv);
      repo = ConstellationAnchorRepository(db);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE public.constellation_anchor, public.constellation_anchor_cursor CASCADE
''');
      // Tests that cascade-delete users or beacons must not poison later ones.
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
SELECT id, id, 'pk-' || id, now(), now()
FROM unnest(ARRAY[${[
        viewer,
        otherViewer,
        person,
        for (var i = 0; i < personCount; i++) personId(i),
      ].map((id) => "'$id'").join(', ')}]) AS id
ON CONFLICT (id) DO NOTHING
''');
      await writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
)
SELECT id, '$person', 't', 'd', 0, true, now(), now(), now()
FROM unnest(ARRAY[${[
        beacon,
        for (var i = 0; i < beaconCount; i++) beaconId(i),
      ].map((id) => "'$id'").join(', ')}]) AS id
ON CONFLICT (id) DO NOTHING
''');
      await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id)
VALUES ('$viewer'), ('$otherViewer')
''');
      await writer.execute('TRUNCATE public.anchor_publisher_probe');
      await settle();
      notifications.clear();
    });

    tearDownAll(() async {
      if (!session.setupComplete) {
        return;
      }
      await notificationSubscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    test(
      'mixed insert, update and delete batch delivers one hint with the '
      'committed cursor revision',
      () async {
        await writer.runTx((tx) async {
          await insertAnchor(tx, viewerId: viewer, personTarget: person);
          await insertAnchor(tx, viewerId: viewer, beaconTarget: beacon);
          await tx.execute(
            '''
UPDATE public.constellation_anchor SET x_units = 5
WHERE viewer_id = '$viewer' AND person_id = '$person'
''',
          );
          await tx.execute(
            '''
DELETE FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND beacon_id = '$beacon'
''',
          );
        });
        await settle();

        final committed = await cursorRevision(viewer);
        final hints = anchorHints(viewer);
        expect(hints, hasLength(1));
        expect(hints.single['event'], 'update');
        expect(hints.single['user_ids'], [viewer]);
        expect(hints.single['revision'], committed.toString());
        expect(await publisherCalls(viewer), 1);
      },
    );

    test(
      'cursor-only bump from a delete of an absent anchor delivers one hint',
      () async {
        final before = await cursorRevision(viewer);

        final result = await repo.deleteAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.person(person),
        );
        await settle();

        final committed = await cursorRevision(viewer);
        expect(committed, greaterThan(before));
        final hints = anchorHints(viewer);
        expect(hints, hasLength(1));
        expect(hints.single['event'], 'update');
        expect(hints.single['revision'], committed.toString());
        expect(result.watermark.revision.value, committed);
        expect(await publisherCalls(viewer), 1);
      },
    );

    test(
      'cascade deleting several anchors in one statement delivers one hint',
      () async {
        await writer.runTx((tx) async {
          await insertAnchor(tx, viewerId: viewer, beaconTarget: beacon);
          await insertAnchor(
            tx,
            viewerId: viewer,
            personTarget: personId(0),
          );
          await insertAnchor(
            tx,
            viewerId: viewer,
            personTarget: personId(1),
          );
        });
        await settle();
        notifications.clear();
        await writer.execute('TRUNCATE public.anchor_publisher_probe');

        await writer.runTx((tx) async {
          await tx.execute(
            '''
DELETE FROM public."user"
WHERE id IN ('${personId(0)}', '${personId(1)}')
''',
          );
          await tx.execute("DELETE FROM public.beacon WHERE id = '$beacon'");
        });
        await settle();

        final committed = await cursorRevision(viewer);
        final hints = anchorHints(viewer);
        expect(hints, hasLength(1));
        expect(hints.single['event'], 'update');
        expect(hints.single['revision'], committed.toString());
        expect(await publisherCalls(viewer), 1);

        final left = await writer.execute(
          '''
SELECT count(*)::int FROM public.constellation_anchor
WHERE viewer_id = '$viewer'
''',
        );
        expect(left.single.single, 0);
      },
    );

    test('rolled back batch delivers no hint and no publisher call', () async {
      final before = await cursorRevision(viewer);

      await expectLater(
        writer.runTx((tx) async {
          await insertAnchor(tx, viewerId: viewer, personTarget: person);
          await insertAnchor(tx, viewerId: viewer, beaconTarget: beacon);
          throw StateError('abort batch');
        }),
        throwsA(isA<StateError>()),
      );
      await settle();

      expect(await cursorRevision(viewer), before);
      expect(anchorHints(), isEmpty);
      expect(await publisherCalls(), 0);
    });

    test(
      'batch of 64 anchor operations makes exactly one publisher call',
      () async {
        await writer.runTx((tx) async {
          for (var i = 0; i < personCount; i++) {
            await insertAnchor(
              tx,
              viewerId: viewer,
              personTarget: personId(i),
              x: i / 4,
            );
          }
          for (var i = 0; i < beaconCount; i++) {
            await insertAnchor(
              tx,
              viewerId: viewer,
              beaconTarget: beaconId(i),
              x: i / 4,
            );
          }
        });
        await settle();

        final committed = await cursorRevision(viewer);
        expect(committed, BigInt.from(64));
        expect(await publisherCalls(viewer), 1);
        final hints = anchorHints(viewer);
        expect(hints, hasLength(1));
        expect(hints.single['revision'], '64');
      },
    );

    test(
      'one transaction touching two viewers publishes once per viewer',
      () async {
        await writer.runTx((tx) async {
          await insertAnchor(tx, viewerId: viewer, personTarget: person);
          await insertAnchor(tx, viewerId: viewer, beaconTarget: beacon);
          await insertAnchor(tx, viewerId: otherViewer, personTarget: person);
        });
        await settle();

        expect(await publisherCalls(viewer), 1);
        expect(await publisherCalls(otherViewer), 1);
        final mine = anchorHints(viewer);
        final theirs = anchorHints(otherViewer);
        expect(mine, hasLength(1));
        expect(theirs, hasLength(1));
        expect(
          mine.single['revision'],
          (await cursorRevision(viewer)).toString(),
        );
        expect(
          theirs.single['revision'],
          (await cursorRevision(otherViewer)).toString(),
        );
      },
    );

    test(
      'separate committed transactions each deliver their own hint',
      () async {
        await writer.runTx(
          (tx) => insertAnchor(tx, viewerId: viewer, personTarget: person),
        );
        final first = await cursorRevision(viewer);
        await writer.runTx(
          (tx) => insertAnchor(tx, viewerId: viewer, beaconTarget: beacon),
        );
        final second = await cursorRevision(viewer);
        await settle();

        expect(second, greaterThan(first));
        final hints = anchorHints(viewer);
        expect(hints.map((h) => h['revision']).toList(), [
          first.toString(),
          second.toString(),
        ]);
        expect(await publisherCalls(viewer), 2);
      },
    );

    test(
      'deleting the viewer publishes nothing for the removed viewer',
      () async {
        await writer.runTx((tx) async {
          await insertAnchor(tx, viewerId: otherViewer, personTarget: person);
        });
        await settle();
        notifications.clear();
        await writer.execute('TRUNCATE public.anchor_publisher_probe');

        await writer.runTx((tx) async {
          await insertAnchor(tx, viewerId: viewer, personTarget: person);
          await tx.execute(
            '''DELETE FROM public."user" WHERE id = '$viewer' ''',
          );
        });
        await settle();

        expect(anchorHints(viewer), isEmpty);
        expect(await publisherCalls(viewer), 0);
      },
    );
  }, skip: skipReason);
}
