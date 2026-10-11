@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/bud_anchor_sweep_repository.dart';
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/use_case/anchor_inherit_operation.dart';
import 'package:tentura_server/domain/use_case/bud_anchor_sweep_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// Budding C8: the anchor inheritance sweep (Arch §8.1) and
/// `ConstellationRequest.parentBeaconId` (Arch §8.2).
///
/// `_post` (author `_author`) admits `_budder`, `_viewer`, `_moved` and
/// `_member` through forward edges. `_child` budded from it by `_budder`;
/// its snapshot observers are `_budder`, `_viewer` and `_moved`, so `_member`
/// (a Post member who is not an observer) cannot read it. `_childReader`
/// reads the child through a forward edge but cannot read the Post.
const _author = 'Ubudanchauth';
const _budder = 'Ubudanchbudr';
const _viewer = 'Ubudanchview';
const _moved = 'Ubudanchmovd';
const _member = 'Ubudanchmemb';
const _childReader = 'Ubudanchrdr1';
const _users = [_author, _budder, _viewer, _moved, _member, _childReader];

const _post = 'Bbudanchpost';
const _child = 'Bbudanchchld';
const _promotedChild = 'Bbudanchprom';

const _command = 'cmd-c8-1';
const _promotedCommand = 'cmd-c8-2';

const _postX = 1.0;
const _postY = -2.0;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BUD_ANCHOR_SWEEP_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_bud_anchor_sweep',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('BudAnchorSweepCase', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late ConstellationAnchorRepository anchors;
    late BudAnchorSweepCase sweep;

    BudAnchorSweepCase newSweep() {
      final port = BudAnchorSweepRepository(database);
      return BudAnchorSweepCase(
        port,
        AnchorInheritOperation(anchors, port),
        env: target.databaseEnv,
        logger: Logger('BudAnchorSweepPgTest'),
      );
    }

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      anchors = ConstellationAnchorRepository(database);
      sweep = newSweep();
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<void> place(String viewer, String beaconId, double x, double y) =>
        anchors.applyBatch(
          viewerId: viewer,
          ops: [
            AnchorApplyOp(
              clientOpId: 'seed:$beaconId:$viewer',
              kind: AnchorOpKind.upsert,
              target: ConstellationAnchorTarget.beacon(beaconId),
              position: ConstellationAnchorPosition(
                xUnits: x,
                yUnits: y,
                coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
              ),
            ),
          ],
        );

    setUp(() async {
      await _seed(writer);
      for (final viewer in [_budder, _viewer, _moved, _member]) {
        await place(viewer, _post, _postX, _postY);
      }
      await place(_moved, _child, 5, 5);
    });

    test('one run anchors the budder and another viewer next to the Post, '
        'keeps a moved anchor, skips a non-reader, marks the row', () async {
      await sweep.run();

      final placed = await _anchorsOn(writer, _child);
      const offset = AnchorInheritOperation.offsetUnits;
      expect(placed.keys, unorderedEquals([_budder, _viewer, _moved]));
      expect(placed[_budder], (_postX + offset, _postY + offset));
      expect(placed[_viewer], (_postX + offset, _postY + offset));
      expect(placed[_moved], (5.0, 5.0));
      expect(placed.containsKey(_member), isFalse);
      expect(await _inheritedAt(writer, _command), isNotNull);
    });

    test('a closed Post hands its own position to the child', () async {
      await writer.execute(
        "UPDATE public.beacon SET status = 6 WHERE id = '$_post'",
      );

      await sweep.run();

      final placed = await _anchorsOn(writer, _child);
      expect(placed[_budder], (_postX, _postY));
      expect(placed[_viewer], (_postX, _postY));
    });

    test('an already-promoted command row is never swept', () async {
      await sweep.run();

      expect(await _anchorsOn(writer, _promotedChild), isEmpty);
      expect(await _inheritedAt(writer, _promotedCommand), isNull);
    });

    test('a second run is a no-op', () async {
      await sweep.run();
      final anchorsBefore = await _anchorsOn(writer, _child);
      final cursorsBefore = await _cursors(writer);

      await sweep.run();

      expect(await _anchorsOn(writer, _child), anchorsBefore);
      expect(await _cursors(writer), cursorsBefore);
    });

    test('two concurrent runs produce one anchor per viewer', () async {
      await Future.wait([sweep.run(), newSweep().run()]);

      final rows = await writer.execute(
        'SELECT viewer_id, count(*)::int FROM public.constellation_anchor '
        "WHERE beacon_id = '$_child' GROUP BY viewer_id ORDER BY viewer_id",
      );
      expect(
        {for (final r in rows) r[0]! as String: r[1]! as int},
        {_budder: 1, _moved: 1, _viewer: 1},
      );
      final ops = await writer.execute(
        'SELECT viewer_id FROM public.constellation_anchor_op_log '
        "WHERE client_op_id LIKE 'bud:%' ORDER BY viewer_id",
      );
      expect([for (final r in ops) r[0]], [_budder, _viewer]);
      // An interrupted overlap leaves the row for the next run, which then
      // finishes it.
      await sweep.run();
      expect(await _inheritedAt(writer, _command), isNotNull);
    });

    test('a replayed op does not re-anchor a child the viewer moved after '
        'inheritance', () async {
      await sweep.run();
      await place(_viewer, _child, -3, -3);
      await writer.execute(
        'UPDATE public.beacon_child_commands SET anchor_inherited_at = NULL',
      );

      await sweep.run();

      expect((await _anchorsOn(writer, _child))[_viewer], (-3.0, -3.0));
    });

    test('nudge is consumed once', () {
      final fresh = newSweep()..nudge();
      expect(fresh.consumeNudge(), isTrue);
      expect(fresh.consumeNudge(), isFalse);
    });

    group('parentBeaconId', () {
      Future<String?> parentFor(String viewer) async {
        final rows = await database
            .customSelect(
              '''
SELECT $constellationRequestSelectColumns
FROM public.beacon b
LEFT JOIN public.image cover ON cover.id = b.cover_thumb_image_id
WHERE b.id = \$2
''',
              variables: [
                Variable.withString(viewer),
                Variable.withString(_child),
              ],
            )
            .get();
        return readConstellationRequestRow(rows.single).parentBeaconId;
      }

      test('is the Post for a viewer who can read it', () async {
        expect(await parentFor(_budder), _post);
      });

      test('is null for a viewer who cannot read the Post', () async {
        expect(await parentFor(_childReader), isNull);
      });
    });
  });
}

Future<Map<String, (double, double)>> _anchorsOn(
  Connection writer,
  String beaconId,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT viewer_id, x_units, y_units FROM public.constellation_anchor '
      'WHERE beacon_id = @b ORDER BY viewer_id',
    ),
    parameters: {'b': beaconId},
  );
  return {
    for (final r in rows) r[0]! as String: (r[1]! as double, r[2]! as double),
  };
}

Future<Map<String, int>> _cursors(Connection writer) async {
  final rows = await writer.execute(
    'SELECT viewer_id, revision::int FROM public.constellation_anchor_cursor',
  );
  return {for (final r in rows) r[0]! as String: r[1]! as int};
}

Future<DateTime?> _inheritedAt(Connection writer, String commandId) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT anchor_inherited_at FROM public.beacon_child_commands '
      'WHERE client_command_id = @c',
    ),
    parameters: {'c': commandId},
  );
  return rows.single.single as DateTime?;
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.constellation_anchor_op_log,
  public.constellation_anchor_target_watermark,
  public.constellation_anchor,
  public.constellation_anchor_cursor,
  public.beacon_child_commands,
  public.beacon_bud_observer,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': _users[i], 'key': pgTestPublicKey('bdanc', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
  for (final (i, member) in [_budder, _viewer, _moved, _member].indexed) {
    await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fbdanc$i', '$_post', '$_author', '$member')
''');
  }
  for (final child in [_child, _promotedChild]) {
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, parent_beacon_id, published_at)
VALUES ('$child', '$_budder', 'Move the piano', '', 0, '$_post', now())
''');
    for (final observer in [_budder, _viewer, _moved, _member]) {
      if (child == _child && observer == _member) continue;
      await writer.execute('''
INSERT INTO public.beacon_bud_observer (beacon_id, user_id)
VALUES ('$child', '$observer')
''');
    }
  }
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fbdancrdr', '$_child', '$_budder', '$_childReader')
''');
  await writer.execute('''
INSERT INTO public.beacon_child_commands
  (actor_user_id, client_command_id, normalized_input_hash, result_beacon_id,
   result_state, bud_result)
VALUES
  ('$_budder', '$_command', 'bud:h1', '$_child', 0,
   '{"outcome":"created","childBeaconId":"$_child","invitees":[]}'),
  ('$_viewer', '$_promotedCommand', 'bud:h2', '$_promotedChild', 2,
   '{"outcome":"alreadyPromoted","childBeaconId":"$_promotedChild","invitees":[]}')
''');
  // Every viewer holds a Post anchor (setUp), so the promoted child would be
  // inherited if its row were swept.
}
