@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// m0239: post→Request budding schema (Arch §2): bud observers, author
/// invites with immutable provenance and the N5 uniqueness, bud columns on
/// `beacon_child_commands`, the forward-edge sweep exemption and the closed
/// Post status.
const _author = 'Um0238author001';
const _member = 'Um0238member001';
const _other = 'Um0238other0001';
const _post = 'Bm0238post00001';
const _child = 'Bm0238child0001';
const _child2 = 'Bm0238child0002';

const _checkViolation = '23514';
const _uniqueViolation = '23505';

Matcher _throwsSqlState(String code) => throwsA(
  isA<ServerException>().having((e) => e.code, 'sqlstate', code),
);

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0239_POST_BUD_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0239_bud_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0239_POST_BUD_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0239_bud',
  );
  final pgSkip =
      await pgSkipReason(migrationTarget) ?? await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: '0238',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('existing rows survive and the new schema is usable', () async {
      final writer = session.writer;
      await _seed(writer);
      await writer.execute('''
INSERT INTO public.beacon_child_commands
  (actor_user_id, client_command_id, normalized_input_hash, result_state)
VALUES ('$_author', 'cmd-m0239-upg', 'h', 0)
''');

      await migrateDbSchema(writer);

      final edge = await writer.execute(
        'SELECT contact_sweep_exempt FROM public.beacon_forward_edge '
        "WHERE id = 'Fm0238edge0001'",
      );
      expect(edge.single.single, isFalse);
      final command = await writer.execute(
        'SELECT bud_result, anchor_inherited_at '
        'FROM public.beacon_child_commands '
        "WHERE client_command_id = 'cmd-m0239-upg'",
      );
      expect(command.single[0], isNull);
      expect(command.single[1], isNull);

      await _insertChild(writer, _child);
      await _invite(writer, 'BIupg', _child, _member);
      await writer.execute(
        'INSERT INTO public.beacon_bud_observer (beacon_id, user_id) '
        "VALUES ('$_child', '$_member')",
      );
      await writer.execute(
        "UPDATE public.beacon SET status = 6 WHERE id = '$_post'",
      );
    });
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
    });

    setUp(() async {
      await _seed(writer);
      await _insertChild(writer, _child);
      await _insertChild(writer, _child2);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    group('N5 uniqueness of pending invites', () {
      test('one pending invite per inviter, invitee and source Post', () async {
        await _invite(writer, 'BI1', _child, _member);
        await expectLater(
          _invite(writer, 'BI2', _child2, _member),
          _throwsSqlState(_uniqueViolation),
        );
      });

      test('a resolved invite does not block a new pending one', () async {
        await _invite(writer, 'BI1', _child, _member, status: 2);
        await _invite(writer, 'BI2', _child2, _member);
        expect(await _inviteCount(writer), 2);
      });

      test('one pending invite per child Request and invitee', () async {
        await _invite(writer, 'BI1', _child, _member, sourcePost: null);
        await expectLater(
          _invite(writer, 'BI2', _child, _member, sourcePost: null),
          _throwsSqlState(_uniqueViolation),
        );
      });

      test('repair invites without a source Post are not N5-bound', () async {
        await _invite(writer, 'BI1', _child, _member, sourcePost: null);
        await _invite(writer, 'BI2', _child2, _member, sourcePost: null);
        expect(await _inviteCount(writer), 2);
      });
    });

    group('immutable provenance', () {
      for (final (column, value) in [
        ('beacon_id', "'$_child2'"),
        ('inviter_id', "'$_other'"),
        ('invitee_id', "'$_other'"),
        ('source_post_id', 'NULL'),
        ('arrival_post_edge_id', "'Fm0238other'"),
        ('warm', 'false'),
      ]) {
        test('$column cannot change', () async {
          await _invite(writer, 'BI1', _child, _member);
          await expectLater(
            writer.execute(
              'UPDATE public.beacon_author_invite SET $column = $value '
              "WHERE id = 'BI1'",
            ),
            _throwsSqlState(_checkViolation),
          );
        });
      }

      test('status, note and resolution may change', () async {
        await _invite(writer, 'BI1', _child, _member);
        await writer.execute('''
UPDATE public.beacon_author_invite
SET status = 1, note = 'n', resolved_at = now(), resolved_by = '$_member',
    forward_edge_id = 'Fm0238edge0001'
WHERE id = 'BI1'
''');
        final row = await writer.execute(
          'SELECT status, resolved_by FROM public.beacon_author_invite',
        );
        expect(row.single[0], 1);
        expect(row.single[1], _member);
      });

      test('deleting the delivery edge clears it without tripping the '
          'guard', () async {
        await _invite(writer, 'BI1', _child, _member);
        await writer.execute('''
UPDATE public.beacon_author_invite SET forward_edge_id = 'Fm0238edge0001'
WHERE id = 'BI1'
''');
        await writer.execute(
          "DELETE FROM public.beacon_forward_edge WHERE id = 'Fm0238edge0001'",
        );
        final row = await writer.execute(
          'SELECT forward_edge_id, arrival_post_edge_id '
          'FROM public.beacon_author_invite',
        );
        expect(row.single[0], isNull);
        expect(row.single[1], 'Fm0238edge0001');
      });
    });

    test('the status check admits 0..5 only', () async {
      for (var s = 0; s <= 5; s++) {
        await _invite(writer, 'BIs$s', _child, _member, status: s);
      }
      for (final s in [-1, 6]) {
        await expectLater(
          _invite(writer, 'BIbad$s', _child, _member, status: s),
          _throwsSqlState(_checkViolation),
        );
      }
    });

    group('Post shape check', () {
      test('a Post may be closed', () async {
        await writer.execute(
          "UPDATE public.beacon SET status = 6 WHERE id = '$_post'",
        );
        await _insertPost(writer, 'Bm0238closed01', status: 6);
      });

      test('a Post is still rejected in statuses 1, 5, 7 and 8', () async {
        for (final s in [1, 5, 7, 8]) {
          await expectLater(
            _insertPost(writer, 'Bm0238badst0$s', status: s),
            _throwsSqlState(_checkViolation),
            reason: 'status $s',
          );
        }
      });
    });

    test('bud observers cascade with the child and the user', () async {
      await writer.execute('''
INSERT INTO public.beacon_bud_observer (beacon_id, user_id)
VALUES ('$_child', '$_member'), ('$_child', '$_other'), ('$_child2', '$_member')
''');
      await writer.execute("DELETE FROM public.\"user\" WHERE id = '$_other'");
      await writer.execute("DELETE FROM public.beacon WHERE id = '$_child2'");
      final rows = await writer.execute(
        'SELECT beacon_id, user_id FROM public.beacon_bud_observer',
      );
      expect(rows.map((r) => [r[0], r[1]]), [
        [_child, _member],
      ]);
    });

    test('the bud indexes exist', () async {
      final rows = await writer.execute('''
SELECT indexname FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('beacon_bud_observer', 'beacon_author_invite',
                    'beacon_child_commands')
''');
      final names = rows.map((r) => r.single! as String).toSet();
      expect(
        names,
        containsAll([
          'beacon_bud_observer_pkey',
          'beacon_bud_observer_user_idx',
          'beacon_author_invite_pkey',
          'beacon_author_invite_pending_source_uq',
          'beacon_author_invite_pending_beacon_uq',
          'beacon_author_invite_pending_invitee_idx',
          'beacon_author_invite_beacon_status_idx',
          'beacon_author_invite_forward_edge_idx',
          'beacon_child_commands_anchor_pending_idx',
        ]),
      );
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_child_commands,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_author, _member, _other];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('m0239', i + 1)},
    );
  }
  await _insertPost(writer, _post, status: 0);
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fm0238edge0001', '$_post', '$_author', '$_member')
''');
}

Future<void> _insertPost(Connection writer, String id, {required int status}) =>
    writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$id', '$_author', '', '', $status, 1, 1, false, now())
''');

Future<void> _insertChild(Connection writer, String id) => writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$id', '$_author', 'Child', '', 0, now())
''');

Future<void> _invite(
  Connection writer,
  String id,
  String beaconId,
  String invitee, {
  String? sourcePost = _post,
  int status = 0,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_author_invite
  (id, beacon_id, inviter_id, invitee_id, source_post_id,
   arrival_post_edge_id, warm, status)
VALUES (@id, @beacon, @inviter, @invitee, @source, @arrival, true, @status)
'''),
  parameters: {
    'id': id,
    'beacon': beaconId,
    'inviter': _author,
    'invitee': invitee,
    'source': sourcePost,
    'arrival': 'Fm0238edge0001',
    'status': status,
  },
);

Future<int> _inviteCount(Connection writer) async =>
    (await writer.execute(
          'SELECT count(*)::int FROM public.beacon_author_invite',
        )).single.single!
        as int;
