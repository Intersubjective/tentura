@Tags(['pg'])
library;

import 'package:migrant/migrant.dart' show Migration;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// #398: before 606aaf7b9 a block withdrew the blocked helper's offer
/// (`status = 1`, `withdraw_reason = 'blocked'`) but left their
/// `beacon_participant` row with `room_access = 3`. The author kept listing
/// an «Active helper» whose offer is withdrawn, while the helper's Requests
/// tab (active offers only, `helpOfferedNonArchived`) stayed empty.
///
/// Since 606aaf7b9 the block calls `revokeOfferUserBeaconRoomAccess`, which
/// sets `room_access = 0` on every non-addressee participant row. The
/// one-off data migration after m0252 repairs the legacy rows the same way:
///
/// - withdrawn + `blocked` + admitted + not an addressee → `room_access = 0`
///   (helpers and stewards alike, on any Request status, closed included);
/// - an addressee (role 6) keeps access, as the revoke does;
/// - an active offer, a withdrawal for another reason (or none, as
///   `deactivate` leaves it) and an already repaired row are untouched;
/// - running the statements again changes nothing;
/// - it is data only: no DDL.
const _author = 'Um0253author01';
const _legacy = 'Um0253legacy01';
const _legacy2 = 'Um0253legacy02';
const _addressee = 'Um0253addrssee1';
const _repaired = 'Um0253repaired1';
const _otherReason = 'Um0253otherrsn1';
const _deactivated = 'Um0253deactivd1';
const _active = 'Um0253active001';
const _steward = 'Um0253steward01';
const _legacyClosed = 'Um0253closed001';
const _users = [
  _author,
  _legacy,
  _legacy2,
  _addressee,
  _repaired,
  _otherReason,
  _deactivated,
  _active,
  _steward,
  _legacyClosed,
];

/// Every legacy row the repair must revoke (a steward too: the revoke skips
/// only addressees; and a closed Request: it ignores the Request status).
const _legacyRows = [_legacy, _legacy2, _steward, _legacyClosed];

const _beacon = 'Bm0253open00001';
const _beacon2 = 'Bm0253needs0001';
const _closedBeacon = 'Bm0253closed001';

const _roleSteward = 1;
const _roleHelper = 2;
const _roleAddressee = 6;
const _admitted = 3;
const _none = 0;

/// A fixed, old timestamp: a row the repair must not touch keeps it.
const _seededAt = '2026-01-01 00:00:00+00';

/// The data migration registered after m0252 that repairs blocked rows.
/// Looked up by content so it does not depend on the number it gets.
Migration _repairMigration() => migrationsForTesting.singleWhere(
  (m) =>
      m.version.compareTo('0252') > 0 &&
      m.statements.any((s) => s.contains("'blocked'")),
);

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0253_BLOCKED_ROOM_ACCESS_REPAIR_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0253_blocked_repair',
  );
  final pgSkip = await pgSkipReason(migrationTarget);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  test('a data-only repair migration is registered after m0252', () {
    final migration = _repairMigration();
    for (final statement in migration.statements) {
      final code = statement.replaceAll(RegExp('--[^\n]*'), '');
      expect(
        RegExp(
          r'\b(CREATE|ALTER|DROP|TRUNCATE|COMMENT\s+ON)\b',
          caseSensitive: false,
        ).hasMatch(code),
        isFalse,
        reason: 'the repair must not change the schema: $statement',
      );
    }
  });

  group('upgrade from m0252 with legacy blocked rows', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late String versionBeforeUpgrade;
    late Map<String, List<Object?>> participantsBefore;
    late Set<String> admittedHelpersBefore;
    late Map<String, List<Object?>> offersBefore;
    late Map<String, List<Object?>> participantsAfter;
    late Set<String> dismissalsBefore;
    late Set<String> dismissalsAfter;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: '0252',
      );
      writer = session.writer;
      await _seed(writer);
      versionBeforeUpgrade =
          (await writer.execute(
                'SELECT max(version COLLATE "C") FROM schema_version',
              )).single.single!
              as String;
      participantsBefore = await _participants(writer);
      admittedHelpersBefore = await _admittedHelpers(writer);
      dismissalsBefore = await _dismissals(writer);
      offersBefore = await _offers(writer);

      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      participantsAfter = await _participants(writer);
      dismissalsAfter = await _dismissals(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('the legacy rows were seeded under m0252, still admitted', () {
      expect(versionBeforeUpgrade, '0252');
      for (final user in _legacyRows) {
        expect(
          participantsBefore[_key(user)]![1],
          _admitted,
          reason: user,
        );
      }
      expect(
        admittedHelpersBefore,
        containsAll(_legacyRows),
        reason: 'the legacy rows are admitted helpers before the repair',
      );
    });

    test('a helper withdrawn by a block loses room access', () {
      for (final user in _legacyRows) {
        final row = participantsAfter[_key(user)]!;
        expect(
          row[0],
          participantsBefore[_key(user)]![0],
          reason: '$user keeps the role',
        );
        expect(row[1], _none, reason: '$user room_access');
        expect(
          row[2],
          participantsBefore[_key(user)]![2],
          reason: '$user keeps the participant status',
        );
      }
      expect(participantsAfter[_key(_steward)]![0], _roleSteward);
    });

    test(
      'the block-withdrawn helper is no longer an admitted helper',
      () async {
        final admitted = await _admittedHelpers(writer);
        expect(admitted.intersection(_legacyRows.toSet()), isEmpty);
      },
    );

    test('the offers themselves are left as they were', () async {
      expect(await _offers(writer), offersBefore);
    });

    test('an addressee, an active offer, another withdrawal and an already '
        'repaired row are untouched', () {
      for (final user in [
        _addressee,
        _active,
        _otherReason,
        _deactivated,
        _repaired,
        _author,
      ]) {
        expect(
          participantsAfter[_key(user)],
          participantsBefore[_key(user)],
          reason: user,
        );
      }
    });

    test('the repair clears the legacy helper offer-accepted dismissal '
        'and keeps the others', () {
      expect(dismissalsBefore, {
        '$_beacon/$_legacy',
        '$_beacon/$_addressee',
        '$_beacon/$_otherReason',
      });
      expect(dismissalsAfter, {
        '$_beacon/$_addressee',
        '$_beacon/$_otherReason',
      });
    });

    test('running the repair again changes nothing', () async {
      for (final statement in _repairMigration().statements) {
        await writer.execute(statement);
      }
      expect(await _participants(writer), participantsAfter);
      expect(await _dismissals(writer), dismissalsAfter);
    });
  });
}

String _key(String user) => switch (user) {
  _legacy2 => '$_beacon2/$user',
  _legacyClosed => '$_closedBeacon/$user',
  _ => '$_beacon/$user',
};

Future<Set<String>> _admittedHelpers(Connection writer) async {
  final rows = await writer.execute(
    'SELECT user_id FROM public.beacon_admitted_helper',
  );
  return {for (final r in rows) r[0]! as String};
}

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
      parameters: {
        'id': _users[i],
        'key': i < 9
            ? pgTestPublicKey('m0253', i + 1)
            : pgTestPublicKey('q0253', i - 8),
      },
    );
  }
  for (final (id, status) in [
    (_beacon, 0),
    (_beacon2, 7),
    (_closedBeacon, 6),
  ]) {
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable, published_at)
VALUES ('$id', '$_author', 'Move the piano', 'Saturday', $status, false, now())
''');
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

  Future<void> offer(
    String beacon,
    String user,
    int status,
    String? reason,
  ) => writer.execute('''
INSERT INTO public.beacon_help_offer
  (beacon_id, user_id, status, withdraw_reason, updated_at)
VALUES ('$beacon', '$user', $status, ${reason == null ? 'NULL' : "'$reason'"},
        '$_seededAt')
''');

  await participant(_beacon, _author, 0, _admitted);
  // Legacy: withdrawn by a block before 606aaf7b9, still admitted.
  await participant(_beacon, _legacy, _roleHelper, _admitted);
  await participant(_beacon2, _legacy2, _roleHelper, _admitted);
  await participant(_beacon, _steward, _roleSteward, _admitted);
  await participant(_closedBeacon, _legacyClosed, _roleHelper, _admitted);
  // The revoke leaves an addressee of a converted Post alone.
  await participant(_beacon, _addressee, _roleAddressee, _admitted);
  // Blocked after 606aaf7b9: already revoked.
  await participant(_beacon, _repaired, _roleHelper, _none);
  // Withdrawn for another reason / deactivated without a reason.
  await participant(_beacon, _otherReason, _roleHelper, _admitted);
  await participant(_beacon, _deactivated, _roleHelper, _admitted);
  // An active offer with a stray reason: only withdrawn offers count.
  await participant(_beacon, _active, _roleHelper, _admitted);

  await offer(_beacon, _legacy, 1, 'blocked');
  await offer(_beacon2, _legacy2, 1, 'blocked');
  await offer(_beacon, _steward, 1, 'blocked');
  await offer(_closedBeacon, _legacyClosed, 1, 'blocked');
  await offer(_beacon, _addressee, 1, 'blocked');
  await offer(_beacon, _repaired, 1, 'blocked');
  await offer(_beacon, _otherReason, 1, 'other');
  await offer(_beacon, _deactivated, 1, null);
  await offer(_beacon, _active, 0, 'blocked');

  // «Offer accepted» dismissals: the revoke clears the legacy one
  // (clearOfferAcceptedDismissal); the guard pairs keep theirs.
  for (final user in [_legacy, _addressee, _otherReason]) {
    await writer.execute('''
INSERT INTO public.offer_accepted_dismissal (user_id, beacon_id)
VALUES ('$user', '$_beacon')
''');
  }
}

/// beacon/user pairs with an «offer accepted» dismissal.
Future<Set<String>> _dismissals(Connection writer) async {
  final rows = await writer.execute(
    'SELECT beacon_id, user_id FROM public.offer_accepted_dismissal',
  );
  return {for (final r in rows) '${r[0]}/${r[1]}'};
}

/// beacon/user → [role, room_access, status, updated_at].
Future<Map<String, List<Object?>>> _participants(Connection writer) async {
  final rows = await writer.execute('''
SELECT beacon_id, user_id, role, room_access, status, updated_at
FROM public.beacon_participant
''');
  return {
    for (final r in rows) '${r[0]}/${r[1]}': [r[2], r[3], r[4], r[5]],
  };
}

/// beacon/user → [status, withdraw_reason, updated_at].
Future<Map<String, List<Object?>>> _offers(Connection writer) async {
  final rows = await writer.execute('''
SELECT beacon_id, user_id, status, withdraw_reason, updated_at
FROM public.beacon_help_offer
''');
  return {
    for (final r in rows) '${r[0]}/${r[1]}': [r[2], r[3], r[4]],
  };
}
