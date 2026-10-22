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
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';

import '../../support/constellation_anchor_batch_fixture.dart';
import '../../support/disposable_pg_target.dart';

/// «Сбросить позиции» (#251, D5): one transaction removes every anchor of the
/// viewer (all target kinds, tombstones too), advances the cursor once more
/// for the reset itself (one realtime hint), stamps the reset watermark so a
/// write made before it is rejected, and replays by operation id.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_ANCHOR_RESET_TEST_DB',
    defaultNamePrefix: 'tentura_test_anchorreset',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Uarsviewer001';
  const otherViewer = 'Uarsviewer002';
  const person = 'Uarsperson001';
  const deletedPerson = 'Uarsperson002';
  const beacon = 'Barsbeacon001';
  const position = ConstellationAnchorPosition(
    xUnits: 3,
    yUnits: -4,
    coordinateSpaceVersion: 1,
  );

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late ConstellationAnchorRepository repo;
  late Connection listener;
  late StreamSubscription<String> subscription;
  final hints = <Map<String, dynamic>>[];

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  Future<int> anchorCount(String viewerId) async =>
      (await db
              .customSelect(
                'SELECT count(*)::int AS c FROM public.constellation_anchor '
                "WHERE viewer_id = '$viewerId'",
              )
              .getSingle())
          .read<int>('c');

  Future<({BigInt revision, BigInt reset})> cursor(String viewerId) async {
    final row = await db
        .customSelect(
          'SELECT revision, reset_revision '
          'FROM public.constellation_anchor_cursor '
          "WHERE viewer_id = '$viewerId'",
        )
        .getSingle();
    return (
      revision: row.read<BigInt>('revision'),
      reset: row.read<BigInt>('reset_revision'),
    );
  }

  Future<AnchorApplyOpResult> upsert(
    ConstellationAnchorTarget target, {
    ConstellationAnchorRevision? baseRevision,
    ConstellationAnchorRevision? ifRevision,
    String? clientOpId,
  }) async => (await repo.applyBatch(
    viewerId: viewer,
    ops: [
      AnchorApplyOp(
        clientOpId: clientOpId ?? 'op-${DateTime.now().microsecondsSinceEpoch}',
        kind: AnchorOpKind.upsert,
        target: target,
        position: position,
        baseRevision: baseRevision,
        ifRevision: ifRevision,
      ),
    ],
  )).results.single;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    db = openDisposablePgDatabase(target);
    repo = constellationAnchorRepositoryFor(db);
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
      'TRUNCATE public.constellation_anchor, public.constellation_anchor_cursor, '
      'public.constellation_anchor_op_log, '
      'public.constellation_anchor_target_watermark CASCADE',
    );
    for (final id in [viewer, otherViewer, person, deletedPerson]) {
      await db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT (id) DO NOTHING
''');
    }
    await db.customStatement('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES ('$beacon', '$person', 't', 'd', 0, true, now(), now(), now())
ON CONFLICT (id) DO NOTHING
''');
    // A person pin, a Request pin, a pin whose target is then deleted
    // (tombstone) and another viewer's pin, which a reset must not touch.
    await repo.applyAnchorUpsert(
      viewerId: viewer,
      context: '',
      target: ConstellationAnchorTarget.person(person),
      position: position,
    );
    await repo.applyAnchorUpsert(
      viewerId: viewer,
      context: '',
      target: ConstellationAnchorTarget.beacon(beacon),
      position: position,
    );
    await repo.applyAnchorUpsert(
      viewerId: viewer,
      context: '',
      target: ConstellationAnchorTarget.person(deletedPerson),
      position: position,
    );
    await repo.applyAnchorUpsert(
      viewerId: otherViewer,
      context: '',
      target: ConstellationAnchorTarget.person(person),
      position: position,
    );
    await db.customStatement(
      "DELETE FROM public.\"user\" WHERE id = '$deletedPerson'",
    );
    await settle();
    hints.clear();
  });

  test('removes every anchor of the viewer, tombstones included', () async {
    expect(await anchorCount(viewer), 3);
    final before = await cursor(viewer);

    final result = await repo.resetAll(viewerId: viewer, clientOpId: 'reset-1');

    expect(result.clearedCount, 3);
    expect(result.replayed, isFalse);
    expect(result.beforeRevision.value, before.revision);
    expect(await anchorCount(viewer), 0);
    expect(await anchorCount(otherViewer), 1);
    final after = await cursor(viewer);
    // One step per removed anchor plus one for the reset itself.
    expect(after.revision, before.revision + BigInt.from(4));
    expect(result.afterRevision.value, after.revision);
    expect(after.reset, after.revision);
  });

  test('emits one anchor hint with the final revision', () async {
    final result = await repo.resetAll(viewerId: viewer, clientOpId: 'reset-1');
    await settle();

    final mine = [
      for (final hint in hints)
        if (hint['id'] == viewer) hint,
    ];
    expect(mine, hasLength(1));
    // The hint carries the cursor revision the reset ended at.
    expect(
      jsonEncode(mine.single),
      contains('"${result.afterRevision.toDecimalString()}"'),
    );
  });

  test('a retry with the same operation id writes nothing again', () async {
    final first = await repo.resetAll(viewerId: viewer, clientOpId: 'reset-1');
    final retry = await repo.resetAll(viewerId: viewer, clientOpId: 'reset-1');

    expect(retry.replayed, isTrue);
    expect(retry.afterRevision, first.afterRevision);
    expect(retry.clearedCount, first.clearedCount);
    expect((await cursor(viewer)).revision, first.afterRevision.value);
  });

  test('an empty reset still moves the cursor and the watermark', () async {
    final first = await repo.resetAll(viewerId: viewer, clientOpId: 'reset-1');
    final second = await repo.resetAll(viewerId: viewer, clientOpId: 'reset-2');

    expect(second.clearedCount, 0);
    expect(second.afterRevision.value, first.afterRevision.value + BigInt.one);
    expect((await cursor(viewer)).reset, second.afterRevision.value);
  });

  test('an operation id of another write is refused', () async {
    await upsert(ConstellationAnchorTarget.person(person), clientOpId: 'op-x');

    await expectLater(
      repo.resetAll(viewerId: viewer, clientOpId: 'op-x'),
      throwsA(isA<ConstellationException>()),
    );
    expect(await anchorCount(viewer), 3);
  });

  group('writes around a reset', () {
    test(
      'a write made before the reset is rejected and changes nothing',
      () async {
        final staleBase = ConstellationAnchorRevision(
          (await cursor(viewer)).revision,
        );
        await repo.resetAll(viewerId: viewer, clientOpId: 'reset-1');

        final result = await upsert(
          ConstellationAnchorTarget.person(person),
          baseRevision: staleBase,
        );

        expect(result.status, AnchorOpStatus.rejected);
        expect(result.reason, 'reset');
        expect(await anchorCount(viewer), 0);
      },
    );

    test('a write based on the reset revision is accepted', () async {
      final reset = await repo.resetAll(
        viewerId: viewer,
        clientOpId: 'reset-1',
      );

      final result = await upsert(
        ConstellationAnchorTarget.person(person),
        baseRevision: reset.afterRevision,
      );

      expect(result.status, AnchorOpStatus.ok);
      expect(await anchorCount(viewer), 1);
    });

    test('a replay of a write rejected for the reset stays rejected', () async {
      final staleBase = ConstellationAnchorRevision(
        (await cursor(viewer)).revision,
      );
      await repo.resetAll(viewerId: viewer, clientOpId: 'reset-1');
      final target = ConstellationAnchorTarget.beacon(beacon);
      await upsert(target, baseRevision: staleBase, clientOpId: 'late-1');

      final replay = await upsert(
        target,
        baseRevision: staleBase,
        clientOpId: 'late-1',
      );

      expect(replay.replayed, isTrue);
      expect(replay.status, AnchorOpStatus.rejected);
      expect(await anchorCount(viewer), 0);
    });

    test(
      'a conditional write on a pre-reset target revision conflicts',
      () async {
        final pin = await upsert(
          ConstellationAnchorTarget.person(person),
          baseRevision: ConstellationAnchorRevision(
            (await cursor(viewer)).revision,
          ),
        );
        await repo.resetAll(viewerId: viewer, clientOpId: 'reset-1');

        final result = await upsert(
          ConstellationAnchorTarget.person(person),
          ifRevision: pin.resultingTargetRevision,
        );

        expect(result.status, AnchorOpStatus.rejected);
        expect(result.reason, 'conflict');
      },
    );

    test('a write without a base revision is not checked', () async {
      await repo.resetAll(viewerId: viewer, clientOpId: 'reset-1');

      final result = await upsert(ConstellationAnchorTarget.person(person));

      expect(result.status, AnchorOpStatus.ok);
    });
  });
}
