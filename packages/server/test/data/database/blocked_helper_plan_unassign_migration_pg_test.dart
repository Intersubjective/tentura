@Tags(['pg'])
library;

import 'package:migrant/migrant.dart' show Migration;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// Before 606aaf7b9 a block withdrew the blocked helper's offer
/// (`status = 1`, `withdraw_reason = 'blocked'`) without freeing their plan
/// steps; the room-access repair after m0252 then took the helper out of the
/// room (`room_access = 0`) but left them assigned (`target_person_id`) to
/// live plan steps (`coordination_item` kind 6, status 0) and with a pending
/// «Понятно» state in `beacon_plan_member`.
///
/// The one-off data migration registered after m0274 does what
/// `BeaconPlanCase.unassignOnLeave` does for such a person:
///
/// - live steps assigned to a block-withdrawn helper who is no longer
///   admitted lose their assignee (the rest of the step stays as it was);
/// - their `pending_from_seq` on that Request is cleared;
/// - an admitted helper, the author, a steward and an addressee keep their
///   steps and pending state, and so do helpers withdrawn for another reason;
/// - removed steps and other Requests are left alone;
/// - applying the statements again changes nothing;
/// - it is data only: no DDL.
const _author = 'Ue0765author01';
const _legacy = 'Ue0765legacy001';
const _admittedHelper = 'Ue0765admitted1';
const _stillAdmitted = 'Ue0765stilladm1';
const _stewardByRole = 'Ue0765steward01';
const _addressee = 'Ue0765addrssee1';
const _otherReason = 'Ue0765otherrsn1';
const _unaffected = 'Ue0765bystandr1';
const _users = [
  _author,
  _legacy,
  _admittedHelper,
  _stillAdmitted,
  _stewardByRole,
  _addressee,
  _otherReason,
  _unaffected,
];

const _beacon = 'Be0765plan00001';
const _otherBeacon = 'Be0765plan00002';

const _roleSteward = 1;
const _roleHelper = 2;
const _roleAddressee = 6;
const _admitted = 3;
const _none = 0;

const _stepLive = 0;
const _stepRemoved = 3;

const _seededAt = '2026-01-01 00:00:00+00';

/// The data migration registered after m0274 that frees plan steps of
/// block-withdrawn helpers. Looked up by content so it does not depend on
/// the number it gets.
List<Migration> _unassignMigrations() => migrationsForTesting
    .where(
      (m) =>
          m.version.compareTo('0274') > 0 &&
          m.statements.any((s) => s.contains('target_person_id')) &&
          m.statements.any((s) => s.contains('beacon_plan_member')),
    )
    .toList();

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BLOCKED_HELPER_PLAN_UNASSIGN_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_blocked_plan_unassign',
  );
  final pgSkip = await pgSkipReason(migrationTarget);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  test('a data-only migration freeing blocked helpers is registered', () {
    final found = _unassignMigrations();
    expect(found, hasLength(1));
    for (final statement in found.single.statements) {
      final code = statement.replaceAll(RegExp('--[^\n]*'), '');
      expect(
        RegExp(
          r'\b(CREATE|ALTER|DROP|TRUNCATE|COMMENT\s+ON)\b',
          caseSensitive: false,
        ).hasMatch(code),
        isFalse,
        reason: 'the migration must not change the schema: $statement',
      );
    }
  });

  group('plan steps of block-withdrawn helpers', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Map<String, List<Object?>> stepsBefore;
    late Map<String, List<Object?>> stepsAfter;
    late Map<String, List<Object?>> membersBefore;
    late Map<String, List<Object?>> membersAfter;
    late Map<String, List<Object?>> participantsBefore;
    late Map<String, List<Object?>> participantsAfter;

    setUpAll(() async {
      final found = _unassignMigrations();
      final all = migrationsForTesting;
      // Seed on the schema as it is just before the migration under test.
      final lastVersion = found.isEmpty
          ? all.last.version
          : all[all.indexOf(found.first) - 1].version;
      session = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: lastVersion,
      );
      writer = session.writer;
      await _seed(writer);
      stepsBefore = await _steps(writer);
      membersBefore = await _members(writer);
      participantsBefore = await _participants(writer);

      for (final migration in found) {
        for (final statement in migration.statements) {
          await writer.execute(statement);
        }
      }
      stepsAfter = await _steps(writer);
      membersAfter = await _members(writer);
      participantsAfter = await _participants(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('the legacy helper is seeded as assigned and not admitted', () {
      for (final id in [_legacyStep1, _legacyStep2]) {
        expect(stepsBefore[id]![_assignee], _legacy, reason: id);
      }
      expect(
        participantsBefore['$_beacon/$_legacy']![1],
        _none,
        reason: 'room_access',
      );
      expect(membersBefore['$_beacon/$_legacy']![0], isNotNull);
    });

    test('every live step of a block-withdrawn, no longer admitted helper '
        'loses its assignee and keeps the rest', () {
      for (final id in [_legacyStep1, _legacyStep2]) {
        final before = stepsBefore[id]!;
        final after = stepsAfter[id]!;
        expect(after[_assignee], isNull, reason: '$id assignee');
        for (final column in [_title, _status, _ordering, _doneAt]) {
          expect(after[column], before[column], reason: '$id column $column');
        }
      }
    });

    test('their pending plan state on that Request is cleared', () {
      final before = membersBefore['$_beacon/$_legacy']!;
      final after = membersAfter['$_beacon/$_legacy']!;
      expect(before[0], isNotNull);
      expect(after[0], isNull, reason: 'pending_from_seq');
      expect(after[1], before[1], reason: 'acked_seq is kept');
    });

    test('an admitted helper, the author, a steward, an addressee, a helper '
        'withdrawn for another reason and a removed step are untouched', () {
      for (final id in [
        _admittedStep,
        _authorStep,
        _stillAdmittedStep,
        _stewardStep,
        _addresseeStep,
        _otherReasonStep,
        _unassignedStep,
        _removedLegacyStep,
        _otherBeaconLegacyStep,
      ]) {
        expect(stepsAfter[id], stepsBefore[id], reason: id);
      }
      for (final key in [
        '$_beacon/$_admittedHelper',
        '$_beacon/$_author',
        '$_beacon/$_stillAdmitted',
        '$_beacon/$_stewardByRole',
        '$_beacon/$_addressee',
        '$_beacon/$_otherReason',
        '$_otherBeacon/$_legacy',
      ]) {
        expect(membersAfter[key], membersBefore[key], reason: key);
      }
    });

    test('rooms and offers are not touched', () {
      expect(participantsAfter, participantsBefore);
    });

    test('applying the migration again changes nothing', () async {
      for (final migration in _unassignMigrations()) {
        for (final statement in migration.statements) {
          await writer.execute(statement);
        }
      }
      expect(await _steps(writer), stepsAfter);
      expect(await _members(writer), membersAfter);
      expect(await _participants(writer), participantsAfter);
    });
  });
}

const _legacyStep1 = 'Se0765legacy0001';
const _legacyStep2 = 'Se0765legacy0002';
const _removedLegacyStep = 'Se0765removed001';
const _admittedStep = 'Se0765admitted01';
const _authorStep = 'Se0765author0001';
const _stillAdmittedStep = 'Se0765stilladm1';
const _stewardStep = 'Se0765steward001';
const _addresseeStep = 'Se0765addressee1';
const _otherReasonStep = 'Se0765otherrsn01';
const _unassignedStep = 'Se0765nobody0001';
const _otherBeaconLegacyStep = 'Se0765otherbcn01';

/// Column positions in the rows returned by [_steps].
const _assignee = 0;
const _title = 1;
const _status = 2;
const _ordering = 3;
const _doneAt = 4;

Future<void> _seed(Connection writer) async {
  await writer.execute(
    'TRUNCATE TABLE public.beacon, public."user" CASCADE',
  );
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': _users[i], 'key': pgTestPublicKey('ea', i + 1)},
    );
  }
  for (final id in [_beacon, _otherBeacon]) {
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable, published_at)
VALUES ('$id', '$_author', 'Move the piano', 'Saturday', 0, false, now())
''');
    await writer.execute(
      "INSERT INTO public.beacon_plan (beacon_id, revision_seq) "
      "VALUES ('$id', 3)",
    );
  }

  Future<void> participant(
    String beacon,
    String user,
    int role,
    int access,
  ) => writer.execute('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, room_access, updated_at)
VALUES ('$beacon', '$user', $role, $access, '$_seededAt')
''');

  Future<void> offer(String beacon, String user, int status, String? reason) =>
      writer.execute('''
INSERT INTO public.beacon_help_offer
  (beacon_id, user_id, status, withdraw_reason, updated_at)
VALUES ('$beacon', '$user', $status, ${reason == null ? 'NULL' : "'$reason'"},
        '$_seededAt')
''');

  Future<void> step(
    String id,
    String beacon,
    String? assignee, {
    int status = _stepLive,
    int ordering = 0,
  }) => writer.execute('''
INSERT INTO public.coordination_item
  (id, beacon_id, kind, status, title, creator_id, target_person_id,
   ordering, published, published_at, created_seq, content_seq, ack_seq,
   removed_seq, updated_at)
VALUES ('$id', '$beacon', 6, $status, 'Step $id', '$_author',
        ${assignee == null ? 'NULL' : "'$assignee'"}, $ordering, true,
        '$_seededAt', 1, 1, 1, ${status == _stepRemoved ? 2 : 'NULL'},
        '$_seededAt')
''');

  Future<void> member(String beacon, String user, int? pendingFrom) =>
      writer.execute('''
INSERT INTO public.beacon_plan_member
  (beacon_id, user_id, pending_from_seq, acked_seq)
VALUES ('$beacon', '$user', ${pendingFrom ?? 'NULL'}, 1)
''');

  await participant(_beacon, _author, 0, _admitted);
  // Legacy: block-withdrawn, taken out of the room by the access repair.
  await participant(_beacon, _legacy, _roleHelper, _none);
  await participant(_beacon, _admittedHelper, _roleHelper, _admitted);
  // Block-withdrawn offer but admitted again: keeps the assignment.
  await participant(_beacon, _stillAdmitted, _roleHelper, _admitted);
  await participant(_beacon, _stewardByRole, _roleSteward, _none);
  await participant(_beacon, _addressee, _roleAddressee, _none);
  // Not in the room, but not block-withdrawn.
  await participant(_beacon, _otherReason, _roleHelper, _none);
  // Admitted on the other Request, where nothing was withdrawn.
  await participant(_otherBeacon, _legacy, _roleHelper, _admitted);

  await offer(_beacon, _legacy, 1, 'blocked');
  await offer(_beacon, _admittedHelper, 0, null);
  await offer(_beacon, _stillAdmitted, 1, 'blocked');
  await offer(_beacon, _stewardByRole, 1, 'blocked');
  await offer(_beacon, _addressee, 1, 'blocked');
  await offer(_beacon, _otherReason, 1, 'other');
  await offer(_otherBeacon, _legacy, 0, null);

  await step(_legacyStep1, _beacon, _legacy, ordering: 1);
  await step(_legacyStep2, _beacon, _legacy, ordering: 2);
  await step(_removedLegacyStep, _beacon, _legacy, status: _stepRemoved);
  await step(_admittedStep, _beacon, _admittedHelper, ordering: 3);
  await step(_authorStep, _beacon, _author, ordering: 4);
  await step(_stillAdmittedStep, _beacon, _stillAdmitted, ordering: 5);
  await step(_stewardStep, _beacon, _stewardByRole, ordering: 6);
  await step(_addresseeStep, _beacon, _addressee, ordering: 7);
  await step(_otherReasonStep, _beacon, _otherReason, ordering: 8);
  await step(_unassignedStep, _beacon, null, ordering: 9);
  await step(_otherBeaconLegacyStep, _otherBeacon, _legacy);

  await member(_beacon, _legacy, 2);
  await member(_beacon, _admittedHelper, 2);
  await member(_beacon, _author, 2);
  await member(_beacon, _stillAdmitted, 2);
  await member(_beacon, _stewardByRole, 2);
  await member(_beacon, _addressee, 2);
  await member(_beacon, _otherReason, 2);
  await member(_otherBeacon, _legacy, 2);
}

/// step id → [target_person_id, title, status, ordering, done_at,
/// content_seq, updated_at]; position constants above name the first five.
Future<Map<String, List<Object?>>> _steps(Connection writer) async {
  final rows = await writer.execute('''
SELECT id, target_person_id, title, status, ordering, done_at, content_seq,
       updated_at
FROM public.coordination_item
WHERE kind = 6
''');
  return {
    for (final r in rows)
      r[0]! as String: [r[1], r[2], r[3], r[4], r[5], r[6], r[7]],
  };
}

/// beacon/user → [pending_from_seq, acked_seq].
Future<Map<String, List<Object?>>> _members(Connection writer) async {
  final rows = await writer.execute('''
SELECT beacon_id, user_id, pending_from_seq, acked_seq
FROM public.beacon_plan_member
''');
  return {
    for (final r in rows) '${r[0]}/${r[1]}': [r[2], r[3]],
  };
}

/// beacon/user → [role, room_access, updated_at].
Future<Map<String, List<Object?>>> _participants(Connection writer) async {
  final rows = await writer.execute('''
SELECT beacon_id, user_id, role, room_access, updated_at
FROM public.beacon_participant
''');
  return {
    for (final r in rows) '${r[0]}/${r[1]}': [r[2], r[3], r[4]],
  };
}
