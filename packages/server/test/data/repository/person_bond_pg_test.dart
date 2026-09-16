@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/person_visibility_repository.dart';

import '../../support/disposable_pg_target.dart';

/// Issue #146 T11: co-participant bond (S4-12) and the D4 proof (S4-13).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERSON_BOND_TEST_DB',
    defaultNamePrefix: 'tentura_test_person_bond',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  const author = 'Upbond_author';
  const viewer = 'Upbond_viewer';
  const helper = 'Upbond_helper';
  const stranger = 'Upbond_strang';
  const shared = 'Bpbond000001';
  const unrelated = 'Bpbond000002';
  const allUsers = [author, viewer, helper, stranger];

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late PersonVisibilityRepository repo;

  Future<void> exec(String sql) => writer.execute(sql);

  Future<bool> bond(String a, String b) async {
    final rows = await writer.execute(
      Sql.named('SELECT public.person_bond(@a, @b)'),
      parameters: {'a': a, 'b': b},
    );
    return rows.first.first! as bool;
  }

  Future<Set<String>> bondPeers(String viewerId) async {
    final rows = await writer.execute(
      Sql.named('SELECT peer_id FROM public.person_bond_peers(@v)'),
      parameters: {'v': viewerId},
    );
    return {for (final r in rows) r.first! as String};
  }

  Future<void> setStatus(String beaconId, int status) => exec(
    "UPDATE public.beacon SET status = $status WHERE id = '$beaconId'",
  );

  Future<void> insertBeacon(
    String id, {
    required String authorId,
    int status = 0,
    bool discoverable = false,
  }) => exec('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable, published_at)
VALUES ('$id', '$authorId', 'Title $id', 'd', $status, $discoverable, now())
''');

  Future<void> block(String blocker, String blocked) => exec('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blocker', '$blocked', '$blocker')
''');

  group('person_bond (S4-12 / S4-13)', () {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      db = openDisposablePgDatabase(target);
      repo = PersonVisibilityRepository(db);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    setUp(() async {
      await exec("DELETE FROM public.beacon WHERE id LIKE 'Bpbond%'");
      await exec(
        "DELETE FROM public.user_block WHERE blocker_id LIKE 'Upbond_%' "
        "OR blocked_id LIKE 'Upbond_%'",
      );
      await exec(
        "DELETE FROM public.vote_user WHERE subject LIKE 'Upbond_%' "
        "OR object LIKE 'Upbond_%'",
      );
      await exec(
        "DELETE FROM public.\"user\" WHERE id LIKE 'Upbond_%'",
      );
      for (final id in allUsers) {
        await exec('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id')
''');
      }
      // Viewer (room_access = 3) and helper (role = 1) are members of the
      // author's shared request; stranger is not.
      await insertBeacon(shared, authorId: author);
      await exec('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$shared', '$viewer', 2, 3), ('$shared', '$helper', 1, 0)
''');
    });

    test('bond exists while the shared request is active', () async {
      for (final status in [0, 5, 7, 8]) {
        await setStatus(shared, status);
        expect(await bond(viewer, author), isTrue, reason: 'status $status');
        expect(await bond(viewer, helper), isTrue, reason: 'status $status');
        expect(await bond(viewer, stranger), isFalse);
      }
    }, skip: skipReason);

    test(
      'bond ends when the request is closed, cancelled, or deleted',
      () async {
        for (final status in [6, 1, 2]) {
          await setStatus(shared, status);
          expect(await bond(viewer, author), isFalse, reason: 'status $status');
          expect(await bond(viewer, helper), isFalse, reason: 'status $status');
          expect(await bondPeers(viewer), isEmpty, reason: 'status $status');
        }
      },
      skip: skipReason,
    );

    test('bond ends when one side stops being a member', () async {
      await exec('''
UPDATE public.beacon_participant SET room_access = 5
WHERE beacon_id = '$shared' AND user_id = '$viewer'
''');
      expect(await bond(viewer, author), isFalse);
      expect(await bond(helper, author), isTrue);

      await exec('''
DELETE FROM public.beacon_participant
WHERE beacon_id = '$shared' AND user_id = '$helper'
''');
      expect(await bond(helper, author), isFalse);
      expect(await bondPeers(author), isEmpty);
    }, skip: skipReason);

    test('blocks kill the bond in either direction', () async {
      await block(viewer, helper);
      expect(await bond(viewer, helper), isFalse);
      expect(await bond(helper, viewer), isFalse);
      expect(await bond(viewer, author), isTrue);

      await exec("DELETE FROM public.user_block WHERE blocker_id = '$viewer'");
      await block(helper, viewer);
      expect(await bond(viewer, helper), isFalse);
      expect(await bond(helper, viewer), isFalse);
    }, skip: skipReason);

    test('bond is symmetric and irreflexive; blank ids never bond', () async {
      for (final a in allUsers) {
        for (final b in allUsers) {
          expect(await bond(a, b), await bond(b, a), reason: '$a/$b');
        }
        expect(await bond(a, a), isFalse);
        expect(await bond(a, ''), isFalse);
      }
    }, skip: skipReason);

    test('person_bond_peers matches person_bond over the fixture', () async {
      await block(helper, author);
      for (final v in allUsers) {
        final expected = {
          for (final x in allUsers)
            if (await bond(v, x)) x,
        };
        expect(await bondPeers(v), expected, reason: v);
        expect(await repo.bondPeerIds(viewerId: v), expected, reason: v);
      }
      // beacon_member drops a participant blocked with the author, so the
      // helper is no longer a member at all: no bond with the viewer either.
      expect(await bondPeers(viewer), {author});
      expect(await bondPeers(helper), isEmpty);
      expect(await bondPeers(author), {viewer});
      expect(await repo.bondPeerIds(viewerId: ''), isEmpty);
    }, skip: skipReason);

    test('person_shared_contexts lists only active shared requests', () async {
      const closed = 'Bpbond000003';
      await insertBeacon(closed, authorId: author, status: 6);
      await exec('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$closed', '$viewer', 2, 3)
''');
      for (var i = 0; i < 25; i++) {
        final id = 'Bpbondmany${i.toString().padLeft(2, '0')}';
        await insertBeacon(id, authorId: author, status: 5);
        await exec('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$id', '$viewer', 2, 3)
''');
      }

      final contexts = await repo.sharedContexts(
        viewerId: viewer,
        peerId: author,
      );
      final ids = contexts.map((c) => c.beaconId).toList();
      expect(ids, hasLength(20));
      expect(ids, isNot(contains(closed)));
      expect(ids.toSet(), hasLength(20));
      expect(contexts.first.title, 'Title ${contexts.first.beaconId}');

      final withHelper = await repo.sharedContexts(
        viewerId: viewer,
        peerId: helper,
      );
      expect(withHelper.map((c) => c.beaconId), [shared]);

      await setStatus(shared, 1);
      expect(
        await repo.sharedContexts(viewerId: viewer, peerId: helper),
        isEmpty,
      );
      expect(
        await repo.sharedContexts(viewerId: viewer, peerId: stranger),
        isEmpty,
      );
      expect(
        await repo.sharedContexts(viewerId: viewer, peerId: viewer),
        isEmpty,
      );
    }, skip: skipReason);

    test(
      'personVisiblePeerIds = trust ∪ bond, minus strangers and blocks',
      () async {
        await exec('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$helper', '$viewer', '$helper')
''');
        final visible = await repo.personVisiblePeerIds(
          viewerId: viewer,
          peerIds: [author, helper, stranger, viewer],
          context: '',
        );
        expect(visible, {author});
        expect(
          await repo.personVisiblePeerIds(
            viewerId: viewer,
            peerIds: const [],
            context: '',
          ),
          isEmpty,
        );
      },
      skip: skipReason,
    );

    test(
      "S4-13: bond does not make the author's discoverable request readable",
      () async {
        await insertBeacon(unrelated, authorId: author, discoverable: true);
        expect(await bond(viewer, author), isTrue);

        final trust = await writer.execute(
          Sql.named(
            "SELECT public.person_are_mutually_visible(@v, @a, '')",
          ),
          parameters: {'v': viewer, 'a': author},
        );
        expect(trust.first.first, isFalse);

        final rows = await writer.execute(
          Sql.named('''
SELECT public.beacon_can_read_content(@b, @v),
       public.beacon_access_reasons(@b, @v) & 32
'''),
          parameters: {'b': unrelated, 'v': viewer},
        );
        expect(rows.first[0], isFalse);
        expect(rows.first[1], 0);

        // Control: the shared request itself stays readable to the member.
        final own = await writer.execute(
          Sql.named('SELECT public.beacon_can_read_content(@b, @v)'),
          parameters: {'b': shared, 'v': viewer},
        );
        expect(own.first.first, isTrue);
      },
      skip: skipReason,
    );
  });
}
