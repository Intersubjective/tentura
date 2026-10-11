@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// Budding B3 (Arch §3.2, I3, I4): the read wall around a Request budded from
/// a Post.
///
/// - contextChild of a Post child is the snapshot `beacon_bud_observer` row,
///   not live Post membership; the Post must not be deleted and the Post
///   author's block still applies.
/// - contextAncestor never grants a Post: members of the child do not read
///   the Post through it.
/// - Request parents keep live-membership shared context (#146).
///
/// Topology:
/// - Post `_post` (author `_postAuthor`) → child Request `_child` (author
///   `_budder`). Snapshot observers: `_postAuthor`, `_observer`,
///   `_obsBlockedPost` (later blocked by the Post author), `_obsBlockedChild`
///   (later blocks the budder). `_late` joined the Post after the bud.
///   `_helper` offered help on the child, `_childFwd` received it by forward,
///   `_childHelper` is an admitted helper of the child (a child member).
/// - Deleted Post `_deadPost` → `_deadChild`, closed Post `_closedPost` →
///   `_closedChild`; `_observer` observes both children.
/// - Request `_req` (author `_reqAuthor`) → `_reqChild`; `_reqMember` is
///   admitted to `_req`, `_reqChildMember` to `_reqChild`.
const _postAuthor = 'Ubudrwpauth01';
const _budder = 'Ubudrwbudder1';
const _observer = 'Ubudrwobserv1';
const _late = 'Ubudrwlate001';
const _obsBlockedPost = 'Ubudrwblkpst1';
const _obsBlockedChild = 'Ubudrwblkchd1';
const _helper = 'Ubudrwhelper1';
const _childFwd = 'Ubudrwchdfwd1';
const _childHelper = 'Ubudrwchdadm1';
const _stranger = 'Ubudrwstrang1';
const _reqAuthor = 'Ubudrwreqaut1';
const _reqMember = 'Ubudrwreqmem1';
const _reqChildMember = 'Ubudrwrqcmem1';

const _users = [
  _postAuthor,
  _budder,
  _observer,
  _late,
  _obsBlockedPost,
  _obsBlockedChild,
  _helper,
  _childFwd,
  _childHelper,
  _stranger,
  _reqAuthor,
  _reqMember,
  _reqChildMember,
];

const _post = 'Bbudrwpost001';
const _child = 'Bbudrwchild01';
const _deadPost = 'Bbudrwdpost01';
const _deadChild = 'Bbudrwdchild1';
const _closedPost = 'Bbudrwcpost01';
const _closedChild = 'Bbudrwcchild1';
const _req = 'Bbudrwreq0001';
const _reqChild = 'Bbudrwreqchd1';

const _beacons = [
  _post,
  _child,
  _deadPost,
  _deadChild,
  _closedPost,
  _closedChild,
  _req,
  _reqChild,
];

/// Expected `beacon_can_read_content` per viewer; beacons not listed are
/// unreadable for that viewer.
const _readable = <String, Set<String>>{
  _postAuthor: {_post, _child, _closedPost, _closedChild},
  _budder: {_post, _child, _closedPost, _closedChild, _deadChild},
  _observer: {_post, _child, _closedPost, _closedChild},
  // Joined the Post after the bud: no snapshot row, no child.
  _late: {_post, _closedPost},
  _obsBlockedPost: {},
  _obsBlockedChild: {_post, _closedPost},
  // Child members and helpers never read the Post through the child.
  _helper: {_child},
  _childFwd: {_child},
  _childHelper: {_child},
  _stranger: {},
  _reqAuthor: {_req, _reqChild},
  // Request-parent shared context is unchanged (#146).
  _reqMember: {_req, _reqChild},
  _reqChildMember: {_req, _reqChild},
};

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_READ_WALL_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_bud_wall_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_READ_WALL_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_bud_wall',
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
        lastInclusiveVersion: '0241',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('rows written before the migration get the new wall', () async {
      final writer = session.writer;
      await _seed(writer);
      // Before: live Post membership reads the child, child members the Post.
      expect(await _canRead(writer, _child, _late), isTrue);
      expect(await _canRead(writer, _post, _childHelper), isTrue);

      await migrateDbSchema(writer);

      expect(await _canRead(writer, _child, _late), isFalse);
      expect(await _canRead(writer, _post, _childHelper), isFalse);
      expect(await _canRead(writer, _child, _observer), isTrue);
    });
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      await _seed(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('beacon_can_read_content leak matrix', () async {
      for (final viewer in _users) {
        for (final beacon in _beacons) {
          expect(
            await _canRead(writer, beacon, viewer),
            _readable[viewer]!.contains(beacon),
            reason: '$viewer @ $beacon',
          );
        }
      }
    });

    test('beacon_readable_ids agrees on every row of the matrix', () async {
      for (final viewer in _users) {
        final rows = await writer.execute(
          Sql.named(
            'SELECT public.beacon_readable_ids(@v, @ids::text[])',
          ),
          parameters: {'v': viewer, 'ids': _beacons},
        );
        expect(
          {for (final r in rows) r.single! as String},
          _readable[viewer],
          reason: viewer,
        );
      }
    });

    test(
      'beacon_access_reasons agrees and never grants a Post by context',
      () async {
        final contextBits =
            BeaconAccessReason.contextChild.bit |
            BeaconAccessReason.contextAncestor.bit;
        for (final viewer in _users) {
          for (final beacon in _beacons) {
            final reasons = await _reasons(writer, beacon, viewer);
            final level = await _level(writer, beacon, viewer);
            expect(
              BeaconAccessLevel.fromInt(level).canReadContent,
              _readable[viewer]!.contains(beacon),
              reason: 'level $viewer @ $beacon',
            );
            if (beacon == _post ||
                beacon == _deadPost ||
                beacon == _closedPost) {
              expect(reasons & contextBits, 0, reason: '$viewer @ $beacon');
            }
          }
        }
        expect(
          await _reasons(writer, _child, _observer),
          BeaconAccessReason.contextChild.bit,
        );
        expect(
          await _reasons(writer, _closedChild, _observer),
          BeaconAccessReason.contextChild.bit,
        );
        expect(await _reasons(writer, _child, _late), 0);
        expect(
          await _reasons(writer, _reqChild, _reqMember),
          BeaconAccessReason.contextChild.bit,
        );
        expect(
          await _reasons(writer, _req, _reqChildMember),
          BeaconAccessReason.contextAncestor.bit,
        );
      },
    );

    test('beacon_can_read_content keeps COST 1000; attributes kept', () async {
      final rows = await writer.execute('''
SELECT p.proname, p.procost::int, p.provolatile::text, p.prosecdef,
       p.proconfig IS NULL
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'beacon_can_read_content', 'beacon_access_reasons', 'beacon_readable_ids'
  )
ORDER BY p.proname
''');
      expect(
        [for (final r in rows) r.toList()],
        [
          ['beacon_access_reasons', 100, 's', false, true],
          ['beacon_can_read_content', 1000, 's', false, true],
          ['beacon_readable_ids', 100, 's', false, true],
        ],
      );
    });
  });
}

Future<bool> _canRead(Connection writer, String beacon, String viewer) async {
  final rows = await writer.execute(
    Sql.named('SELECT public.beacon_can_read_content(@b, @v)'),
    parameters: {'b': beacon, 'v': viewer},
  );
  return rows.single.single! as bool;
}

Future<int> _reasons(Connection writer, String beacon, String viewer) async {
  final rows = await writer.execute(
    Sql.named('SELECT public.beacon_access_reasons(@b, @v)'),
    parameters: {'b': beacon, 'v': viewer},
  );
  return rows.single.single! as int;
}

Future<int> _level(Connection writer, String beacon, String viewer) async {
  final rows = await writer.execute(
    Sql.named('SELECT public.beacon_access_level(@b, @v)'),
    parameters: {'b': beacon, 'v': viewer},
  );
  return rows.single.single! as int;
}

Future<void> _seed(Connection writer) async {
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {
        'id': _users[i],
        // Nine slots per namespace.
        'key': pgTestPublicKey(i < 9 ? 'bw' : 'bx', i % 9 + 1),
      },
    );
  }
  Future<void> post(String id) => writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$id', '$_postAuthor', '', '', 0, 1, 1, false, now())
''');
  Future<void> request(String id, String author, String? parent) =>
      writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable,
   parent_beacon_id, published_at)
VALUES ('$id', '$author', 'Request', '', 0, false,
        ${parent == null ? 'NULL' : "'$parent'"}, now())
''');
  var edgeSeq = 0;
  // Forward edges admit their recipients (m0210).
  Future<void> forward(String beacon, String sender, String recipient) =>
      writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fbudrw${(edgeSeq++).toString().padLeft(4, '0')}', '$beacon',
        '$sender', '$recipient')
''');
  Future<void> observe(String beacon, String user) => writer.execute('''
INSERT INTO public.beacon_bud_observer (beacon_id, user_id)
VALUES ('$beacon', '$user')
''');
  Future<void> admit(String beacon, String user) => writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('P$beacon$user', '$beacon', '$user', 0, 0, 3)
''');

  for (final p in [_post, _deadPost, _closedPost]) {
    await post(p);
    for (final member in [
      _budder,
      _observer,
      _late,
      _obsBlockedPost,
      _obsBlockedChild,
    ]) {
      await forward(p, _postAuthor, member);
    }
  }
  for (final (p, c) in [
    (_post, _child),
    (_deadPost, _deadChild),
    (_closedPost, _closedChild),
  ]) {
    await request(c, _budder, p);
    for (final o in [
      _postAuthor,
      _observer,
      _obsBlockedPost,
      _obsBlockedChild,
    ]) {
      await observe(c, o);
    }
  }
  await forward(_child, _budder, _childFwd);
  await admit(_child, _childHelper);
  await writer.execute('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status)
VALUES ('$_child', '$_helper', '', 0)
''');
  await writer.execute(
    "UPDATE public.beacon SET status = 2 WHERE id = '$_deadPost'",
  );
  await writer.execute(
    "UPDATE public.beacon SET status = 6 WHERE id = '$_closedPost'",
  );
  await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_postAuthor', '$_obsBlockedPost', '$_postAuthor'),
       ('$_obsBlockedChild', '$_budder', '$_obsBlockedChild')
''');

  await request(_req, _reqAuthor, null);
  await request(_reqChild, _reqAuthor, _req);
  await admit(_req, _reqMember);
  await admit(_reqChild, _reqChildMember);
}
