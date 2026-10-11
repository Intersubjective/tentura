@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// m0245 (budding C4, Arch §5.4): pending author invites expire when their
/// Request goes terminal (1, 2, 6), in the same transaction, with the
/// delivery contact resolved without evidence. Review (5) and its reopen do
/// not expire them; Posts and already-terminal Requests are not touched.
///
/// The fixtures have no inbox rows, so the m0213 inbox triggers stay out of
/// the way; receipts and the full entry points are covered by
/// `author_invite_case_pg_test.dart`.
const _author = 'Um0244author1';
const _invitee = 'Um0244invitee';
const _other = 'Um0244other01';
const _post = 'Bm0244post001';
const _child = 'Bm0244child01';
const _sibling = 'Bm0244sibling';

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0245_INVITE_EXPIRY_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0245_expiry_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0245_INVITE_EXPIRY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0245_expiry',
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
        lastInclusiveVersion: '0244',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('an invite written before the migration expires on cancel', () async {
      final writer = session.writer;
      await _seed(writer);
      final invite = await _invite(writer, _child, _invitee);

      await migrateDbSchema(writer);
      await _setStatus(writer, _child, 1);

      expect(await _inviteStatus(writer, invite), 4);
    });
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
    });

    setUp(() async => _seed(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    for (final (from, to) in [(0, 1), (0, 2), (0, 6), (7, 1), (8, 6), (5, 6)]) {
      test(
        '$from → $to expires pending invites and resolves the contact',
        () async {
          await _setStatus(writer, _child, from);
          final edge = await _edge(writer, _child, _invitee);
          final pending = await _invite(writer, _child, _invitee, edge: edge);
          final accepted = await _invite(
            writer,
            _child,
            _other,
            status: 1,
          );
          final elsewhere = await _invite(writer, _sibling, _other);

          await _setStatus(writer, _child, to);

          expect(await _inviteStatus(writer, pending), 4);
          expect(await _resolvedAt(writer, pending), isNotNull);
          expect(await _inviteStatus(writer, accepted), 1);
          expect(await _inviteStatus(writer, elsewhere), 0);
          final contact = await _contact(writer, edge);
          expect(contact.resolvedAt, isNotNull);
          expect(contact.outcome, isNull);
          expect(await _evidenceCount(writer), 0);
        },
      );
    }

    test('review and reopen (0 → 5 → 7) keep the invite pending', () async {
      final invite = await _invite(writer, _child, _invitee);

      await _setStatus(writer, _child, 5);
      expect(await _inviteStatus(writer, invite), 0);
      await _setStatus(writer, _child, 7);
      expect(await _inviteStatus(writer, invite), 0);
      await _setStatus(writer, _child, 8);
      expect(await _inviteStatus(writer, invite), 0);
    });

    test('a terminal → terminal step does not fire again', () async {
      await _setStatus(writer, _child, 1);
      final late = await _invite(writer, _child, _invitee);

      await _setStatus(writer, _child, 2);

      expect(await _inviteStatus(writer, late), 0);
    });

    test('a Post going terminal touches no invite', () async {
      final invite = await _invite(writer, _child, _invitee);

      await _setStatus(writer, _post, 6);
      await _setStatus(writer, _post, 2);

      expect(await _inviteStatus(writer, invite), 0);
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.trust_evidence,
  public.beacon_author_invite,
  public.inbox_item,
  public.beacon_forward_edge,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_author, _invitee, _other];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('m0245', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, false, now())
''');
  for (final id in [_child, _sibling]) {
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, parent_beacon_id,
   published_at)
VALUES ('$id', '$_author', 'Request', 'desc', 0, '$_post', now())
''');
  }
}

Future<void> _setStatus(Connection writer, String beacon, int status) =>
    writer.execute(
      Sql.named('UPDATE public.beacon SET status = @s WHERE id = @b'),
      parameters: {'s': status, 'b': beacon},
    );

/// A tracked edge author → [recipient] on [beacon]. Its inbox row is removed
/// so the m0213 inbox triggers have nothing to move.
Future<String> _edge(Connection writer, String beacon, String recipient) async {
  final rows = await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES (@b, @s, @r)
RETURNING id, contact_deadline_at IS NOT NULL
'''),
    parameters: {'b': beacon, 's': _author, 'r': recipient},
  );
  expect(rows.single[1], isTrue, reason: 'a tracked contact');
  await writer.execute(
    Sql.named('DELETE FROM public.inbox_item WHERE beacon_id = @b'),
    parameters: {'b': beacon},
  );
  return rows.single[0]! as String;
}

Future<String> _invite(
  Connection writer,
  String beacon,
  String invitee, {
  String? edge,
  int status = 0,
}) async {
  final rows = await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_author_invite
  (beacon_id, inviter_id, invitee_id, source_post_id, forward_edge_id, warm,
   status)
VALUES (@b, @a, @i, @p, @e, false, @s)
RETURNING id
'''),
    parameters: {
      'b': beacon,
      'a': _author,
      'i': invitee,
      'p': _post,
      'e': edge,
      's': status,
    },
  );
  return rows.single.single! as String;
}

Future<int> _inviteStatus(Connection writer, String id) async =>
    (await writer.execute(
          Sql.named(
            'SELECT status FROM public.beacon_author_invite WHERE id = @id',
          ),
          parameters: {'id': id},
        )).single.single!
        as int;

Future<DateTime?> _resolvedAt(Connection writer, String id) async =>
    (await writer.execute(
          Sql.named(
            'SELECT resolved_at FROM public.beacon_author_invite '
            'WHERE id = @id',
          ),
          parameters: {'id': id},
        )).single.single
        as DateTime?;

Future<({int? outcome, DateTime? resolvedAt})> _contact(
  Connection writer,
  String edge,
) async {
  final row = (await writer.execute(
    Sql.named(
      'SELECT contact_outcome, contact_resolved_at '
      'FROM public.beacon_forward_edge WHERE id = @id',
    ),
    parameters: {'id': edge},
  )).single;
  return (outcome: row[0] as int?, resolvedAt: row[1] as DateTime?);
}

Future<int> _evidenceCount(Connection writer) async =>
    (await writer.execute(
          'SELECT count(*)::int FROM public.trust_evidence',
        )).single.single!
        as int;
