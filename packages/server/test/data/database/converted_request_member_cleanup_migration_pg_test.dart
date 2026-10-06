@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/consts/beacon_participant_status_bits.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _previousVersion = '0223';
const _cleanupVersion = '0224';
const _author = 'Uconvertedcleanupauthor';
const _steward = 'Uconvertedcleanupsteward';
const _helper = 'Uconvertedcleanuphelper';
const _members = [
  'UconvertedcleanupmemberA',
  'UconvertedcleanupmemberB',
  'UconvertedcleanupmemberC',
];
const _convertedRequests = ['BcleanupconvertedA', 'BcleanupconvertedB'];
const _regularRequest = 'Bcleanupregularrequest';
const _post = 'Bcleanuppost';
const _postWithConversionMessage = 'Bcleanuppostwithmarker';
const _requestWithOtherSystemMessage = 'Bcleanuprequestothermarker';

Future<void> main() async {
  test(
    'registers the converted Request member cleanup migration',
    () {
      expect(
        migrationsForTesting.where(
          (migration) => migration.version == _cleanupVersion,
        ),
        hasLength(1),
        reason:
            'Converted Request member cleanup must be registered at $_cleanupVersion',
      );
    },
  );

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONVERTED_REQUEST_MEMBER_CLEANUP_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_converted_cleanup',
  );
  final pgSkip = await pgSkipReason(target);

  group(
    'member cleanup for previously converted Requests',
    () {
      late DisposablePgWriterSession session;
      late Connection writer;

      setUpAll(() async {
        session = await setUpDisposablePgWriter(
          target: target,
          lastInclusiveVersion: _previousVersion,
        );
        writer = session.writer;
        await _seed(writer);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session);
      });

      test(
        'removes exactly converted Request addressees and remains safe to replay',
        () async {
          final cleanupMigrations = migrationsForTesting.where(
            (migration) => migration.version == _cleanupVersion,
          );
          expect(cleanupMigrations, hasLength(1));
          final cleanupMigration = cleanupMigrations.single;
          final participantsBefore = await _tableSnapshot(
            writer,
            'beacon_participant',
          );
          final beaconsBefore = await _tableSnapshot(writer, 'beacon');
          final messagesBefore = await _tableSnapshot(
            writer,
            'beacon_room_message',
          );
          final expectedParticipants = participantsBefore.where((participant) {
            final isConvertedRequest = _convertedRequests.contains(
              participant['beacon_id'],
            );
            return !isConvertedRequest ||
                participant['role'] != BeaconParticipantRoleBits.addressee;
          }).toList();
          expect(
            participantsBefore.length - expectedParticipants.length,
            5,
            reason: 'Both converted Requests have legacy members to remove',
          );

          await migrateDbSchemaThrough(writer, cleanupMigration.version);

          expect(
            await _tableSnapshot(writer, 'beacon_participant'),
            expectedParticipants,
            reason:
                'Only role=addressee rows on kind=Request beacons with the conversion system message are removed',
          );
          expect(await _tableSnapshot(writer, 'beacon'), beaconsBefore);
          expect(
            await _tableSnapshot(writer, 'beacon_room_message'),
            messagesBefore,
          );

          // Replaying the statements checks real idempotence, rather than only
          // migrant's normal shortcut for an already recorded schema version.
          await writer.runTx((transaction) async {
            for (final statement in cleanupMigration.statements) {
              await transaction.execute(statement);
            }
          });

          expect(
            await _tableSnapshot(writer, 'beacon_participant'),
            expectedParticipants,
          );
          expect(await _tableSnapshot(writer, 'beacon'), beaconsBefore);
          expect(
            await _tableSnapshot(writer, 'beacon_room_message'),
            messagesBefore,
          );

          await migrateDbSchemaThrough(writer, cleanupMigration.version);
          expect(
            await _tableSnapshot(writer, 'beacon_participant'),
            expectedParticipants,
          );
        },
      );
    },
    skip: pgSkip,
  );
}

Future<List<Map<String, dynamic>>> _tableSnapshot(
  Connection writer,
  String table,
) async => (await writer.execute(
  'SELECT to_jsonb(entry) FROM public.$table entry ORDER BY entry.id',
)).map((row) => Map<String, dynamic>.from(row.single! as Map)).toList();

Future<void> _seed(Connection writer) async {
  await writer.execute('TRUNCATE TABLE public.beacon, public."user" CASCADE');
  final users = [_author, _steward, _helper, ..._members];
  for (var index = 0; index < users.length; index++) {
    final id = users[index];
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('cm', index + 1)},
    );
  }

  for (final (beaconId, kind, systemMessageKind) in [
    (_convertedRequests[0], 0, BeaconRoomSystemMessageKind.convertedToRequest),
    (_convertedRequests[1], 0, BeaconRoomSystemMessageKind.convertedToRequest),
    (_regularRequest, 0, null),
    (_post, 1, null),
    (
      _postWithConversionMessage,
      1,
      BeaconRoomSystemMessageKind.convertedToRequest,
    ),
    (
      _requestWithOtherSystemMessage,
      0,
      BeaconRoomSystemMessageKind.childCreated,
    ),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES (@id, @author, @title, @description, 0, @kind, 1, false, now())
'''),
      parameters: {
        'id': beaconId,
        'author': _author,
        'title': kind == 0 ? 'Move a piano' : '',
        'description': kind == 0 ? 'Carry a piano down three floors.' : '',
        'kind': kind,
      },
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, system_message_kind, system_payload)
VALUES (@id, @beacon, @author, '', @kind, '{}'::jsonb)
'''),
      parameters: {
        'id': 'Rcleanup$beaconId',
        'beacon': beaconId,
        'author': _author,
        'kind': systemMessageKind,
      },
    );

    for (final (userId, role, status, access) in [
      (
        _author,
        BeaconParticipantRoleBits.author,
        BeaconParticipantStatusBits.watching,
        RoomAccessBits.admitted,
      ),
      (
        _steward,
        BeaconParticipantRoleBits.steward,
        BeaconParticipantStatusBits.watching,
        RoomAccessBits.admitted,
      ),
      (
        _helper,
        BeaconParticipantRoleBits.helper,
        BeaconParticipantStatusBits.admitted,
        RoomAccessBits.admitted,
      ),
      (
        _members[0],
        BeaconParticipantRoleBits.addressee,
        BeaconParticipantStatusBits.watching,
        RoomAccessBits.admitted,
      ),
      (
        _members[1],
        BeaconParticipantRoleBits.addressee,
        BeaconParticipantStatusBits.watching,
        RoomAccessBits.left,
      ),
      if (beaconId == _convertedRequests[0])
        (
          _members[2],
          BeaconParticipantRoleBits.addressee,
          BeaconParticipantStatusBits.watching,
          RoomAccessBits.none,
        ),
    ]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @beacon, @user, @role, @status, @access)
'''),
        parameters: {
          'id': 'Pcleanup$beaconId$userId',
          'beacon': beaconId,
          'user': userId,
          'role': role,
          'status': status,
          'access': access,
        },
      );
    }
  }
}
