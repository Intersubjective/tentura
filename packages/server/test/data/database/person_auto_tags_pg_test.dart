@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// `person_auto_tags(viewer, peers)`: the facts-derived tags every viewer
/// gets for free, one row per (peer, kind), computed without any MeritRank
/// call and never for a blocked peer.
const _mutualContact = 0;
const _iTrust = 1;
const _trustsMe = 2;
const _helpedMe = 3;
const _iHelped = 4;
const _workedTogether = 5;
const _invited = 6;
const _forwarded = 7;
const _newOnField = 8;

const _viewer = 'Uautoviewer001';
const _mutual = 'Uautomutual001';
const _oneWayOut = 'Uautooneout01';
const _oneWayIn = 'Uautoonein001';
const _helper = 'Uautohelper001';
const _author = 'Uautoauthor001';
const _steward = 'Uautosteward01';
const _cancelledHelper = 'Uautocancel001';
const _reopenedHelper = 'Uautoreopen001';
const _deletedPeer = 'Uautodeleted01';
const _invitedMe = 'Uautoinvme0001';
const _iInvited = 'Uautoiinv00001';
const _invitedBoth = 'Uautoinvboth01';
const _fwdTo = 'Uautofwdto0001';
const _fwdFrom = 'Uautofwdfrom01';
const _fresh = 'Uautofresh0001';
const _stale = 'Uautostale0001';
const _blocked = 'Uautoblocked01';
const _blockedBy = 'Uautoblockedby';

const _allUsers = [
  _viewer,
  _mutual,
  _oneWayOut,
  _oneWayIn,
  _helper,
  _author,
  _steward,
  _cancelledHelper,
  _reopenedHelper,
  _deletedPeer,
  _invitedMe,
  _iInvited,
  _invitedBoth,
  _fwdTo,
  _fwdFrom,
  _fresh,
  _stale,
  _blocked,
  _blockedBy,
];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERSON_AUTO_TAGS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_person_auto_tags',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('person_auto_tags', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    Future<void> sql(String statement) => writer.execute(statement);

    Future<void> vote(String from, String to) => sql(
      'INSERT INTO public.vote_user (subject, object, amount) '
      "VALUES ('$from', '$to', 1)",
    );

    Future<void> beacon(String id, String authorId, int status) => sql('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at, created_at,
   status_changed_at)
VALUES ('$id', '$authorId', 'Request', 'd', $status, 0,
  now() - interval '30 days', now() - interval '30 days',
  now() - interval '30 days')
''');

    Future<void> admittedHelper(String beaconId, String userId) => sql('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$beaconId', '$userId', 1, 3)
''');

    Future<void> steward(String beaconId, String userId) => sql(
      'INSERT INTO public.beacon_steward (beacon_id, user_id) '
      "VALUES ('$beaconId', '$userId')",
    );

    Future<void> invite(String from, String to) => sql('''
INSERT INTO public.invitation (user_id, invited_id, invite_origin, accepted_at)
VALUES ('$from', '$to', 'existing_account', now())
''');

    Future<void> forward(String beaconId, String from, String to) => sql('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$beaconId', '$from', '$to')
''');

    Future<void> firstSeen(String peer, String ago) => sql('''
INSERT INTO public.person_field_first_seen (viewer_id, peer_id, first_seen_at)
VALUES ('$_viewer', '$peer', now() - interval '$ago')
''');

    /// peer -> kind -> (n, direction)
    Future<Map<String, Map<int, ({int n, int direction})>>> tags({
      String viewer = _viewer,
      List<String>? peers,
    }) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT peer_id, kind, n, direction '
          'FROM public.person_auto_tags(@viewer, @peers)',
        ),
        parameters: {'viewer': viewer, 'peers': peers},
      );
      final out = <String, Map<int, ({int n, int direction})>>{};
      for (final r in rows) {
        (out[r[0]! as String] ??= {})[r[1]! as int] = (
          n: r[2]! as int,
          direction: r[3]! as int,
        );
      }
      return out;
    }

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      for (final id in _allUsers) {
        await sql('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id')
''');
      }

      await vote(_viewer, _mutual);
      await vote(_mutual, _viewer);
      await vote(_viewer, _oneWayOut);
      await vote(_oneWayIn, _viewer);

      // Request in review: author is the viewer, helper is admitted.
      await beacon('Bauto0000001', _viewer, 5);
      await admittedHelper('Bauto0000001', _helper);
      // Request in review by someone else, the viewer helped.
      await beacon('Bauto0000002', _author, 6);
      await admittedHelper('Bauto0000002', _viewer);
      // Cancelled / reopened Requests with an admitted helper.
      await beacon('Bauto0000003', _viewer, 1);
      await admittedHelper('Bauto0000003', _cancelledHelper);
      await beacon('Bauto0000004', _viewer, 5);
      await admittedHelper('Bauto0000004', _reopenedHelper);
      await sql(
        "UPDATE public.beacon SET status = 0 WHERE id = 'Bauto0000004'",
      );
      // Worked together: two Requests with the steward, one of them the
      // steward is also a participant of nothing else.
      await beacon('Bauto0000005', _viewer, 0);
      await steward('Bauto0000005', _steward);
      await beacon('Bauto0000006', _viewer, 0);
      await steward('Bauto0000006', _steward);
      // Deleted Request: its member must not count.
      await beacon('Bauto0000007', _viewer, 2);
      await steward('Bauto0000007', _deletedPeer);

      await invite(_invitedMe, _viewer);
      await invite(_viewer, _iInvited);
      await invite(_invitedBoth, _viewer);
      await invite(_viewer, _invitedBoth);

      await forward('Bauto0000005', _viewer, _fwdTo);
      await forward('Bauto0000005', _fwdFrom, _viewer);

      await firstSeen(_fresh, '3 days');
      await firstSeen(_stale, '8 days');

      for (final id in [_blocked, _blockedBy]) {
        await vote(_viewer, id);
        await vote(id, _viewer);
        await admittedHelper('Bauto0000005', id);
      }
      await sql('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_viewer', '$_blocked', '$_viewer'),
       ('$_blockedBy', '$_viewer', '$_blockedBy')
''');
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('is a STABLE function that makes no MeritRank call', () async {
      final rows = await writer.execute('''
SELECT provolatile::text, prosrc FROM pg_proc
WHERE proname = 'person_auto_tags' AND pronamespace = 'public'::regnamespace
''');
      expect(rows, hasLength(1));
      expect(rows.single[0], 's');
      expect(rows.single[1], isNot(contains('mr_')));
    });

    group('trust kinds', () {
      test('reciprocal trust is a mutual contact only', () async {
        final t = await tags();
        expect(t[_mutual]!.keys, contains(_mutualContact));
        expect(t[_mutual]!.keys, isNot(contains(_iTrust)));
        expect(t[_mutual]!.keys, isNot(contains(_trustsMe)));
      });

      test('one-way trust gives I trust or Trusts me', () async {
        final t = await tags();
        expect(t[_oneWayOut]!.keys, contains(_iTrust));
        expect(t[_oneWayOut]!.keys, isNot(contains(_mutualContact)));
        expect(t[_oneWayIn]!.keys, contains(_trustsMe));
        expect(t[_oneWayIn]!.keys, isNot(contains(_mutualContact)));
      });
    });

    group('helping', () {
      test('request in review or closed: Helped me / I helped', () async {
        final t = await tags();
        expect(t[_helper]!.keys, contains(_helpedMe));
        expect(t[_helper]!.keys, isNot(contains(_iHelped)));
        expect(t[_author]!.keys, contains(_iHelped));
        expect(t[_author]!.keys, isNot(contains(_helpedMe)));
      });

      test('a cancelled Request gives neither', () async {
        final t = await tags();
        final kinds = t[_cancelledHelper]?.keys ?? const <int>[];
        expect(kinds, isNot(contains(_helpedMe)));
        expect(kinds, isNot(contains(_iHelped)));
      });

      test('a reopened Request gives neither', () async {
        final t = await tags();
        final kinds = t[_reopenedHelper]?.keys ?? const <int>[];
        expect(kinds, isNot(contains(_helpedMe)));
        expect(kinds, isNot(contains(_iHelped)));
      });
    });

    group('worked together', () {
      test('counts distinct co-member Requests', () async {
        final t = await tags();
        expect(t[_steward]![_workedTogether]!.n, 2);
      });

      test('an author who is also a steward counts a Request once', () async {
        await beacon('Bauto0000008', _author, 0);
        await steward('Bauto0000008', _author);
        await admittedHelper('Bauto0000008', _viewer);
        final t = await tags(peers: [_author]);
        // Bauto0000002 (viewer participant, author) + Bauto0000008 once.
        expect(t[_author]![_workedTogether]!.n, 2);
      });

      test('a deleted Request does not count', () async {
        final t = await tags();
        expect(
          t[_deletedPeer]?.keys ?? const <int>[],
          isNot(contains(_workedTogether)),
        );
      });
    });

    group('invitations', () {
      test('direction 1 when they invited me', () async {
        final t = await tags();
        expect(t[_invitedMe]![_invited]!.direction, 1);
      });

      test('direction 2 when I invited them', () async {
        final t = await tags();
        expect(t[_iInvited]![_invited]!.direction, 2);
      });

      test('direction 3 when both invited each other', () async {
        final t = await tags();
        expect(t[_invitedBoth]![_invited]!.direction, 3);
      });

      test('other kinds carry direction 0', () async {
        final t = await tags();
        expect(t[_mutual]![_mutualContact]!.direction, 0);
      });
    });

    test('a forward edge in either direction gives Forwarded', () async {
      final t = await tags();
      expect(t[_fwdTo]!.keys, contains(_forwarded));
      expect(t[_fwdFrom]!.keys, contains(_forwarded));
    });

    group('new on the Field', () {
      test('first seen 3 days ago is New', () async {
        final t = await tags();
        expect(t[_fresh]!.keys, contains(_newOnField));
      });

      test('first seen 8 days ago is not New', () async {
        final t = await tags();
        expect(t[_stale]?.keys ?? const <int>[], isNot(contains(_newOnField)));
      });
    });

    test('blocked peers have no rows in either direction', () async {
      final t = await tags();
      expect(t, isNot(contains(_blocked)));
      expect(t, isNot(contains(_blockedBy)));
    });

    test('the peer list restricts the output', () async {
      final t = await tags(peers: [_mutual]);
      expect(t.keys, [_mutual]);
    });
  });
}
