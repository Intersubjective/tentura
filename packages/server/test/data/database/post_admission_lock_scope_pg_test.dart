@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';

import '../../support/disposable_pg_target.dart';

/// Post admission runs under the per-Post advisory lock alone: reconciling an
/// addressee neither needs nor takes the global hierarchy lock, while every
/// other write to `beacon_participant` still serialises on it.
const _author = 'Upostadmlock001';
const _sender = 'Upostadmlock002';
const _addressee = 'Upostadmlock003';
const _bystander = 'Upostadmlock004';

const _post = 'Bpostadmlock001';
const _otherPost = 'Bpostadmlock002';
const _request = 'Bpostadmlock003';

const _statusOpen = 0;

const _roleAddressee = BeaconParticipantRoleBits.addressee;
const _roleHelper = BeaconParticipantRoleBits.helper;
const _accessNone = RoomAccessBits.none;
const _accessAdmitted = RoomAccessBits.admitted;

const _hierarchyKey = "hashtextextended('tentura.beacon_hierarchy.v1', 0)";

/// Records what `tentura.post_admission` is while a participant row is written.
const _probeTable = 'public.post_admission_lock_scope_probe';

/// The failure the probe trigger raises for [_bystander] writes.
const _probeFailure = 'post_admission_lock_scope_probe_failure';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_ADMISSION_LOCK_SCOPE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_adm_lock',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Post admission lock scope', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      for (final id in [_author, _sender, _addressee, _bystander]) {
        await _insertUser(writer, id);
      }
      await _installProbe(writer);
    });

    setUp(() async {
      await _insertPost(writer, _post);
      await _insertPost(writer, _otherPost);
      await _insertRequest(writer, _request);
    });

    tearDown(() async {
      await writer.execute('ROLLBACK');
      await writer.execute('DELETE FROM $_probeTable');
      await writer.execute(
        "DELETE FROM public.beacon_forward_edge WHERE beacon_id LIKE 'Bpostadmlock%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_participant WHERE beacon_id LIKE 'Bpostadmlock%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon WHERE id LIKE 'Bpostadmlock%'",
      );
    });

    tearDownAll(() async {
      await writer.execute('DROP TABLE IF EXISTS $_probeTable CASCADE');
      await writer.execute(
        'DROP FUNCTION IF EXISTS public.post_admission_lock_scope_probe_fn() '
        'CASCADE',
      );
      await tearDownDisposablePgWriter(session: session);
    });

    group('forward edge to an open Post under the Post lock only', () {
      test(
        'admits the recipient and holds the Post lock but not the hierarchy '
        'lock',
        () async {
          await writer.execute('BEGIN');
          await _lockPost(writer, _post);

          await _forward(writer, 'Fpostadmlk0001', _post, _sender, _addressee);

          expect(
            await _participant(writer, _post, _addressee),
            (role: _roleAddressee, access: _accessAdmitted),
          );
          expect(
            await _holdsPostLock(writer, _post),
            isTrue,
            reason: 'the Post advisory lock stays granted until commit',
          );
          expect(
            await _holdsHierarchyLock(writer),
            isFalse,
            reason: 'admitting an addressee must not take the global lock',
          );
          await writer.execute('COMMIT');
        },
      );

      test(
        'cancelling the last live edge withdraws access without the '
        'hierarchy lock',
        () async {
          await _forward(writer, 'Fpostadmlk0002', _post, _sender, _addressee);
          expect(
            await _participant(writer, _post, _addressee),
            (role: _roleAddressee, access: _accessAdmitted),
          );

          await writer.execute('BEGIN');
          await _lockPost(writer, _post);
          await writer.execute(
            'UPDATE public.beacon_forward_edge SET cancelled_at = now() '
            "WHERE id = 'Fpostadmlk0002'",
          );

          expect(
            await _participant(writer, _post, _addressee),
            (role: _roleAddressee, access: _accessNone),
          );
          expect(await _holdsHierarchyLock(writer), isFalse);
          await writer.execute('COMMIT');
        },
      );
    });

    group('other participant writes keep the hierarchy lock', () {
      test('a raw participant insert on a Request holds it', () async {
        await writer.execute('BEGIN');
        expect(await _holdsHierarchyLock(writer), isFalse);

        await _insertParticipant(writer, _request, _addressee, _roleHelper);

        expect(await _holdsHierarchyLock(writer), isTrue);
        await writer.execute('COMMIT');
      });

      test('a raw participant insert on a Post holds it', () async {
        await writer.execute('BEGIN');

        await _insertParticipant(writer, _post, _addressee, _roleHelper);

        expect(await _holdsHierarchyLock(writer), isTrue);
        await writer.execute('COMMIT');
      });

      test(
        'a raw participant update holds it',
        () async {
          await _insertParticipant(writer, _request, _addressee, _roleHelper);

          await writer.execute('BEGIN');
          await writer.execute(
            'UPDATE public.beacon_participant SET room_access = 0 '
            "WHERE beacon_id = '$_request' AND user_id = '$_addressee'",
          );

          expect(await _holdsHierarchyLock(writer), isTrue);
          await writer.execute('COMMIT');
        },
      );

      test(
        'a raw participant insert after an admission in the same '
        'transaction still holds it',
        () async {
          await writer.execute('BEGIN');
          await _lockPost(writer, _post);
          await writer.execute(
            "SELECT public.post_reconcile_admission('$_post', '$_addressee')",
          );
          expect(
            await _holdsHierarchyLock(writer),
            isFalse,
            reason: 'the admission itself does not take the global lock',
          );

          await _insertParticipant(writer, _request, _sender, _roleHelper);

          expect(await _holdsHierarchyLock(writer), isTrue);
          await writer.execute('COMMIT');
        },
      );
    });

    group('post_reconcile_admission', () {
      test(
        'writes the participant row with the admission marker on and '
        'restores it afterwards',
        () async {
          await _forward(writer, 'Fpostadmlk0003', _post, _sender, _addressee);

          final seen = await _probeSettings(writer);
          expect(seen, isNotEmpty);
          expect(
            seen,
            everyElement('on'),
            reason: 'every participant write is made while the marker is on',
          );
          expect(await _admissionSetting(writer), isNot('on'));
        },
      );

      test(
        'restores the marker when the reconcile raises after setting it',
        () async {
          await expectLater(
            _forward(writer, 'Fpostadmlk0004', _post, _sender, _bystander),
            throwsA(
              predicate<Object>(
                (e) => e.toString().contains('$_probeFailure:on'),
                'fails while the admission marker is on',
              ),
            ),
          );

          expect(await _admissionSetting(writer), isNot('on'));

          // A failed call inside a transaction, rolled back to a savepoint.
          await writer.execute('BEGIN');
          await _lockPost(writer, _post);
          await writer.execute('SAVEPOINT admission_failure');
          await expectLater(
            writer.execute(
              "SELECT public.post_reconcile_admission('$_post', '$_bystander')",
            ),
            throwsA(
              predicate<Object>(
                (e) => e.toString().contains('$_probeFailure:on'),
              ),
            ),
          );
          await writer.execute('ROLLBACK TO SAVEPOINT admission_failure');

          expect(await _admissionSetting(writer), isNot('on'));
          await writer.execute('COMMIT');
        },
      );

      test(
        'takes the Post lock itself when the caller holds none',
        () async {
          await writer.execute('BEGIN');
          expect(await _holdsPostLock(writer, _post), isFalse);

          await writer.execute(
            "SELECT public.post_reconcile_admission('$_post', '$_addressee')",
          );

          expect(await _holdsPostLock(writer, _post), isTrue);
          expect(
            await _holdsPostLock(writer, _otherPost),
            isFalse,
            reason: 'only the reconciled Post is locked',
          );
          await writer.execute('COMMIT');
        },
      );

      test(
        'takes no Post lock when the beacon is not a Post it can admit to',
        () async {
          await writer.execute('BEGIN');

          await writer.execute(
            "SELECT public.post_reconcile_admission('$_request', '$_addressee')",
          );
          await writer.execute(
            "SELECT public.post_reconcile_admission('$_post', '$_author')",
          );

          expect(await _holdsPostLock(writer, _request), isFalse);
          expect(await _holdsPostLock(writer, _post), isFalse);
          await writer.execute('COMMIT');
        },
      );
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

Future<void> _insertParticipant(
  Connection writer,
  String beaconId,
  String userId,
  int role,
) => writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('$beaconId', '$userId', $role, $_accessAdmitted)
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

/// The lock `PostLockRepository` takes for a Post, without the hierarchy lock.
Future<void> _lockPost(Connection writer, String beaconId) => writer.execute(
  "SELECT pg_advisory_xact_lock(hashtextextended('$beaconId', 4242))",
);

Future<bool> _holdsPostLock(Connection writer, String beaconId) =>
    _holdsAdvisory(writer, "hashtextextended('$beaconId', 4242)");

Future<bool> _holdsHierarchyLock(Connection writer) =>
    _holdsAdvisory(writer, _hierarchyKey);

/// Whether this backend holds the granted advisory lock [keyExpr]. Scoped to
/// this database, that key and this pid: `pg_locks` is cluster-wide and the
/// migrate advisory lock is visible in every database.
Future<bool> _holdsAdvisory(Connection writer, String keyExpr) async {
  final rows = await writer.execute(
    'SELECT 1 FROM pg_locks l '
    "WHERE l.locktype = 'advisory' AND l.granted AND l.objsubid = 1 "
    'AND ((l.classid::bigint << 32) | l.objid::bigint) = $keyExpr '
    'AND l.pid = pg_backend_pid() AND l.database = '
    '(SELECT oid FROM pg_database WHERE datname = current_database())',
  );
  return rows.isNotEmpty;
}

Future<String?> _admissionSetting(Connection writer) async =>
    (await writer.execute(
          "SELECT current_setting('tentura.post_admission', true)",
        )).single.single
        as String?;

Future<List<String?>> _probeSettings(Connection writer) async => [
  for (final r in await writer.execute(
    'SELECT setting FROM $_probeTable ORDER BY id',
  ))
    r.single as String?,
];

/// A test-only row trigger on `beacon_participant`: it records the admission
/// marker seen by every write to [_addressee], and fails writes to [_bystander]
/// with the marker value in the message.
Future<void> _installProbe(Connection writer) async {
  await writer.execute('''
CREATE TABLE $_probeTable (
  id serial PRIMARY KEY,
  setting text
)
''');
  await writer.execute('''
CREATE FUNCTION public.post_admission_lock_scope_probe_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS \$\$
BEGIN
  IF NEW.user_id = '$_bystander' THEN
    RAISE EXCEPTION '$_probeFailure:%',
      coalesce(current_setting('tentura.post_admission', true), 'unset');
  END IF;
  IF NEW.user_id = '$_addressee' THEN
    INSERT INTO $_probeTable (setting)
    VALUES (current_setting('tentura.post_admission', true));
  END IF;
  RETURN NEW;
END
\$\$
''');
  await writer.execute('''
CREATE TRIGGER post_admission_lock_scope_probe_trg
AFTER INSERT OR UPDATE ON public.beacon_participant
FOR EACH ROW EXECUTE FUNCTION public.post_admission_lock_scope_probe_fn()
''');
}
