@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// m0210: a forward edge to a Post admits the recipient as an addressee
/// (`role 6`, `room_access 3`) and cancelling the last live edge withdraws that
/// admission; addressees are not admitted helpers; Posts create no person bond.
/// See `docs/plans/post-and-constellation-composer-plan.md` §4.2.
const _author = 'Um0210author01';
const _sender = 'Um0210sender01';
const _addressee = 'Um0210addres01';
const _otherSender = 'Um0210sender02';
const _otherAddressee = 'Um0210addres02';

const _post = 'Bm0210post001';
const _request = 'Bm0210reqst001';

const _statusOpen = 0;

const _roleAddressee = BeaconParticipantRoleBits.addressee;
const _roleSteward = BeaconParticipantRoleBits.steward;
const _roleHelper = BeaconParticipantRoleBits.helper;

const _accessNone = RoomAccessBits.none;
const _accessAdmitted = RoomAccessBits.admitted;
const _accessLeft = RoomAccessBits.left;

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0210_POST_ADMISSION_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0210_adm_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0210_POST_ADMISSION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0210_adm',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: '0209',
      );
      final writer = session.writer;
      for (final id in [_author, _sender, _addressee, _otherAddressee]) {
        await _insertUser(writer, id);
      }
      await _insertPost(writer, _post);
      // Written while no admission trigger exists.
      await _forward(writer, 'Fm0210upg0001', _post, _sender, _addressee);
      expect(await _participant(writer, _post, _addressee), isNull);

      await migrateDbSchema(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('installs the admission reconcile function', () async {
      final rows = await session.writer.execute(
        "SELECT to_regprocedure('public.post_reconcile_admission(text, text)')::text",
      );
      expect(rows.single.single, isNotNull);
    });

    test(
      'a forward edge written before the migration is not backfilled into '
      'an admission',
      () async {
        expect(await _participant(session.writer, _post, _addressee), isNull);
        expect(await _isMember(session.writer, _post, _addressee), isFalse);
      },
    );

    test(
      'a forward edge written after the migration admits its recipient',
      () async {
        await _forward(
          session.writer,
          'Fm0210upg0002',
          _post,
          _sender,
          _otherAddressee,
        );

        expect(
          await _participant(session.writer, _post, _otherAddressee),
          (role: _roleAddressee, access: _accessAdmitted),
        );
      },
    );
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      for (final id in [
        _author,
        _sender,
        _addressee,
        _otherSender,
        _otherAddressee,
      ]) {
        await _insertUser(writer, id);
      }
    });

    setUp(() async {
      await _insertPost(writer, _post);
      await _insertRequest(writer, _request);
    });

    tearDown(() async {
      await writer.execute(
        "DELETE FROM public.beacon_forward_edge WHERE beacon_id LIKE 'Bm0210%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_participant WHERE beacon_id LIKE 'Bm0210%'",
      );
      await writer.execute("DELETE FROM public.beacon WHERE id LIKE 'Bm0210%'");
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test(
      'forward edges fire the admission function on insert and on cancel',
      () async {
        final rows = await writer.execute('''
SELECT t.tgtype
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE t.tgrelid = 'public.beacon_forward_edge'::regclass
  AND NOT t.tgisinternal
  AND p.proname = 'post_admission_on_forward_edge'
''');
        const insertBit = 4;
        const updateBit = 16;
        final types = [for (final r in rows) r.single! as int];
        expect(
          types.where((t) => t & insertBit != 0),
          hasLength(1),
          reason: 'one trigger fires on INSERT',
        );
        expect(
          types.where((t) => t & updateBit != 0),
          hasLength(1),
          reason: 'one trigger fires on UPDATE',
        );
      },
    );

    group('admission by forward edge', () {
      test(
        'a forward to a published post admits the recipient as an '
        'addressee, a member of the post and not an admitted helper',
        () async {
          await _forward(writer, 'Fm0210adm0001', _post, _sender, _addressee);

          expect(
            await _participant(writer, _post, _addressee),
            (role: _roleAddressee, access: _accessAdmitted),
          );
          expect(await _isMember(writer, _post, _addressee), isTrue);
          expect(await _isAdmittedHelper(writer, _post, _addressee), isFalse);
        },
      );

      test('a forward to a request creates no participant row', () async {
        await _forward(writer, 'Fm0210adm0002', _request, _sender, _addressee);

        expect(await _participant(writer, _request, _addressee), isNull);
      });

      test(
        'a forward of a post to its author creates no participant row',
        () async {
          await _forward(writer, 'Fm0210adm0003', _post, _sender, _author);

          expect(await _participant(writer, _post, _author), isNull);
        },
      );

      test(
        'a forward edge written the way accepting an invitation writes it '
        'admits the invitee',
        () async {
          // The sharer reached the post through a normal forward, then shares
          // it by invitation: the accepted invite materializes an edge
          // sharer -> invitee whose parent is the sharer's own inbound edge,
          // inserted without an explicit id and with ON CONFLICT DO NOTHING.
          await _forward(writer, 'Fm0210inv0001', _post, _sender, _otherSender);
          await writer.execute('''
INSERT INTO public.beacon_forward_edge
  (beacon_id, sender_id, recipient_id, note, parent_edge_id)
VALUES ('$_post', '$_otherSender', '$_addressee', '', 'Fm0210inv0001')
ON CONFLICT DO NOTHING
''');

          expect(
            await _participant(writer, _post, _otherSender),
            (role: _roleAddressee, access: _accessAdmitted),
          );
          expect(
            await _participant(writer, _post, _addressee),
            (role: _roleAddressee, access: _accessAdmitted),
          );
          expect(await _isMember(writer, _post, _addressee), isTrue);
        },
      );
    });

    group('withdrawal on cancel', () {
      test('cancelling the only edge withdraws the admission', () async {
        await _forward(writer, 'Fm0210can0001', _post, _sender, _addressee);
        expect(
          await _participant(writer, _post, _addressee),
          (role: _roleAddressee, access: _accessAdmitted),
        );

        await _cancel(writer, 'Fm0210can0001');

        expect(
          await _participant(writer, _post, _addressee),
          (role: _roleAddressee, access: _accessNone),
        );
        expect(await _isMember(writer, _post, _addressee), isFalse);
      });

      test(
        'cancelling one of two live edges keeps the admission, cancelling '
        'both withdraws it',
        () async {
          await _forward(writer, 'Fm0210can0002', _post, _sender, _addressee);
          await _forward(
            writer,
            'Fm0210can0003',
            _post,
            _otherSender,
            _addressee,
          );

          await _cancel(writer, 'Fm0210can0002');
          expect(
            await _participant(writer, _post, _addressee),
            (role: _roleAddressee, access: _accessAdmitted),
          );

          await _cancel(writer, 'Fm0210can0003');
          expect(
            await _participant(writer, _post, _addressee),
            (role: _roleAddressee, access: _accessNone),
          );
        },
      );

      test(
        'a new edge after a withdrawal admits the recipient again',
        () async {
          await _forward(writer, 'Fm0210can0004', _post, _sender, _addressee);
          await _cancel(writer, 'Fm0210can0004');
          await _forward(
            writer,
            'Fm0210can0005',
            _post,
            _otherSender,
            _addressee,
          );

          expect(
            await _participant(writer, _post, _addressee),
            (role: _roleAddressee, access: _accessAdmitted),
          );
        },
      );
    });

    group('addressee who left', () {
      Future<void> seedLeftAddressee() => writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$_post', '$_addressee', $_roleAddressee, $_accessLeft)
''');

      test('a new forward edge does not readmit them', () async {
        await seedLeftAddressee();

        await _forward(
          writer,
          'Fm0210lft0001',
          _post,
          _otherSender,
          _addressee,
        );

        expect(
          await _participant(writer, _post, _addressee),
          (role: _roleAddressee, access: _accessLeft),
        );
      });

      test('cancelling every edge leaves them as they were', () async {
        await seedLeftAddressee();
        await _forward(writer, 'Fm0210lft0002', _post, _sender, _addressee);
        await _forward(
          writer,
          'Fm0210lft0003',
          _post,
          _otherSender,
          _addressee,
        );

        await _cancel(writer, 'Fm0210lft0002');
        await _cancel(writer, 'Fm0210lft0003');

        expect(
          await _participant(writer, _post, _addressee),
          (role: _roleAddressee, access: _accessLeft),
        );
      });
    });

    group('other roles', () {
      test(
        'a steward row is unchanged by a forward and by its cancel',
        () async {
          await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$_post', '$_addressee', $_roleSteward, $_accessAdmitted)
''');

          await _forward(writer, 'Fm0210stw0001', _post, _sender, _addressee);
          expect(
            await _participant(writer, _post, _addressee),
            (role: _roleSteward, access: _accessAdmitted),
          );

          await _cancel(writer, 'Fm0210stw0001');
          expect(
            await _participant(writer, _post, _addressee),
            (role: _roleSteward, access: _accessAdmitted),
          );
        },
      );
    });

    group('beacon_admitted_helper', () {
      test(
        'excludes an admitted addressee but keeps other admitted roles',
        () async {
          await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$_post', '$_addressee', $_roleAddressee, $_accessAdmitted),
       ('$_post', '$_otherAddressee', $_roleHelper, $_accessAdmitted)
''');

          expect(await _isAdmittedHelper(writer, _post, _addressee), isFalse);
          expect(
            await _isAdmittedHelper(writer, _post, _otherAddressee),
            isTrue,
          );
        },
      );
    });

    group('person bond', () {
      test('two addressees of one post are not bonded', () async {
        await _forward(writer, 'Fm0210bnd0001', _post, _sender, _addressee);
        await _forward(
          writer,
          'Fm0210bnd0002',
          _post,
          _sender,
          _otherAddressee,
        );
        expect(await _isMember(writer, _post, _addressee), isTrue);
        expect(await _isMember(writer, _post, _otherAddressee), isTrue);

        expect(await _bond(writer, _addressee, _otherAddressee), isFalse);
        expect(await _bondPeers(writer, _addressee), isEmpty);
        expect(
          await _sharedContexts(writer, _addressee, _otherAddressee),
          isEmpty,
        );
      });

      test('two helpers of an open request are still bonded', () async {
        await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$_request', '$_addressee', $_roleHelper, $_accessAdmitted),
       ('$_request', '$_otherAddressee', $_roleHelper, $_accessAdmitted)
''');

        expect(await _bond(writer, _addressee, _otherAddressee), isTrue);
        expect(await _bondPeers(writer, _addressee), {
          _author,
          _otherAddressee,
        });
        expect(
          await _sharedContexts(writer, _addressee, _otherAddressee),
          [_request],
        );
      });
    });
  });
}

typedef _Participant = ({int role, int access});

Future<void> _insertUser(Connection writer, String id) => writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');

Future<void> _insertPost(Connection writer, String id) => writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at)
VALUES ('$id', '$_author', '', '', $_statusOpen, 1, false, now())
''');

Future<void> _insertRequest(Connection writer, String id) => writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$id', '$_author', 'Request', 'd', $_statusOpen, now())
''');

Future<void> _forward(
  Connection writer,
  String id,
  String beaconId,
  String senderId,
  String recipientId,
) => writer.execute('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id)
VALUES ('$id', '$beaconId', '$senderId', '$recipientId')
''');

Future<void> _cancel(Connection writer, String edgeId) => writer.execute('''
UPDATE public.beacon_forward_edge SET cancelled_at = now() WHERE id = '$edgeId'
''');

Future<_Participant?> _participant(
  Connection writer,
  String beaconId,
  String userId,
) async {
  final rows = await writer.execute('''
SELECT role, room_access FROM public.beacon_participant
WHERE beacon_id = '$beaconId' AND user_id = '$userId'
''');
  if (rows.isEmpty) return null;
  return (role: rows.single[0]! as int, access: rows.single[1]! as int);
}

Future<bool> _isMember(
  Connection writer,
  String beaconId,
  String userId,
) async => (await writer.execute('''
SELECT 1 FROM public.beacon_member
WHERE beacon_id = '$beaconId' AND user_id = '$userId'
''')).isNotEmpty;

Future<bool> _isAdmittedHelper(
  Connection writer,
  String beaconId,
  String userId,
) async => (await writer.execute('''
SELECT 1 FROM public.beacon_admitted_helper
WHERE beacon_id = '$beaconId' AND user_id = '$userId'
''')).isNotEmpty;

Future<bool> _bond(Connection writer, String a, String b) async =>
    (await writer.execute(
          "SELECT public.person_bond('$a', '$b')",
        )).single.single!
        as bool;

Future<Set<String>> _bondPeers(Connection writer, String viewerId) async => {
  for (final r in await writer.execute(
    "SELECT peer_id FROM public.person_bond_peers('$viewerId')",
  ))
    r.single! as String,
};

Future<List<String>> _sharedContexts(
  Connection writer,
  String viewerId,
  String peerId,
) async => [
  for (final r in await writer.execute(
    "SELECT beacon_id FROM public.person_shared_contexts('$viewerId', '$peerId')",
  ))
    r.first! as String,
];
