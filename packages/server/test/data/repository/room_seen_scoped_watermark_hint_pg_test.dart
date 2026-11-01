@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_notification_recorder.dart';
import '../../support/pg_test_public_keys.dart';
import '../../api/controllers/websocket/websocket_realtime_protocol_test.dart'
    show fanOutPrivateReadCursor;
import '../../../../client/test/features/realtime/read_cursor_server_frames.dart';

/// The reader's private hint must carry enough information for another tab
/// to advance exactly one room's unread cursor without refetching the room.
/// General uses an explicit null thread_item_id; Questions uses its item id.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SCOPED_SEEN_HINT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_scoped_seen_hint',
  );
  final skipReason = await pgSkipReason(target);
  late DisposablePgWriterSession session;
  late TenturaDb db;
  late BeaconRoomRepository room;
  late Connection listener;
  late PgNotificationRecorder recorder;
  const readerId = 'Uc0ffee000001';
  const beaconId = 'Bscopedseen1';
  const questionsId = 'CIscopedques';

  Future<void> barrier(String token) => session.writer.execute(
    Sql.named("SELECT pg_notify('entity_changes', @payload)"),
    parameters: {
      'payload': jsonEncode({'entity': 'barrier', 'id': token}),
    },
  );

  setUpAll(() async {
    if (skipReason != null) return;
    session = await setUpDisposablePgWriter(target: target);
    db = TenturaDb(target.databaseEnv);
    room = BeaconRoomRepository(db);
    listener = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    await listener.execute('LISTEN entity_changes');
    recorder = PgNotificationRecorder(listener.channels['entity_changes']);
    await session.writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key)',
      ),
      parameters: {'id': readerId, 'key': pgTestPublicKey('scopedseen', 1)},
    );
    await session.writer.execute(
      Sql.named(
        'INSERT INTO public.beacon (id, user_id, title, description) '
        "VALUES (@id, @reader, 'Read hint', '')",
      ),
      parameters: {'id': beaconId, 'reader': readerId},
    );
    // This is the production Questions exception, not a dormant item thread.
    // No discussion_internal_fixture override: the m0254 guard must allow it.
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.coordination_item
  (id, beacon_id, kind, status, title, body, creator_id, published,
   created_at, updated_at, published_at, source, ordering)
VALUES (@id, @beacon, 7, 0, 'Questions', '', @reader, true,
        now(), now(), now(), 0, 0)
'''),
      parameters: {'id': questionsId, 'beacon': beaconId, 'reader': readerId},
    );
  });

  tearDownAll(() async {
    if (skipReason != null) return;
    await recorder.cancel();
    await listener.close();
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  group('Private room read hints identify the persisted cursor', () {
    for (final scope in <String?>[null, questionsId]) {
      test(
        scope == null
            ? 'Discussion read hint delivers its scope and timestamp to the reader'
            : 'Questions read hint delivers its scope and timestamp to the reader',
        () async {
          // Test both creation (INSERT) and advancement (UPDATE); a cursor on
          // the first read alone would leave the next read in another tab
          // stale, and one on updates alone would miss a tab's first read.
          for (final (at, event) in [
            (DateTime.utc(2026, 10, 30, 12), 'insert'),
            (DateTime.utc(2026, 10, 30, 13), 'update'),
          ]) {
            await recorder.drain(sendBarrier: barrier);
            final persisted = await room.markBeaconRoomSeen(
              userId: readerId,
              beaconId: beaconId,
              threadItemId: scope,
              at: at,
            );
            expect(persisted, at);
            await recorder.flush(sendBarrier: barrier);
            final hints = recorder.messages
                .where(
                  (hint) =>
                      hint['entity'] == 'room_seen' && hint['id'] == beaconId,
                )
                .toList();
            expect(hints, hasLength(1));
            final hint = hints.single;
            expect(hint['user_ids'], [
              readerId,
            ], reason: 'Private read convergence is addressed to the reader');
            expect(hint['event'], event);
            expect(
              hint,
              containsPair('thread_item_id', scope),
              reason: 'Explicit scope distinguishes Discussion from Questions',
            );
            expect(
              hint['last_seen_at'],
              isA<String>(),
              reason: 'Another session needs the persisted watermark',
            );
            expect(DateTime.parse(hint['last_seen_at'] as String).toUtc(), at);
            // Client tests start from the contract fixture; it must describe
            // exactly what this trigger publishes.
            final contract = roomSeenReadCursorNotification(
              readerId: readerId,
              beaconId: beaconId,
              at: at,
              event: event,
              threadItemId: scope,
            );
            expect(
              _normalised(hint),
              _normalised(contract),
              reason: 'The real NOTIFY and the shared contract must agree',
            );
            // Deliver the real NOTIFY through production websocket fan-out to
            // two signed-in tabs of the reader, actor echo on and off.
            for (final echo in [true, false]) {
              final real = await fanOutPrivateReadCursor(
                hint,
                actorEcho: echo,
              );
              for (final tab in [real.first, real.second]) {
                expect(
                  tab,
                  hasLength(1),
                  reason:
                      'Every tab of the reader receives its cursor (echo $echo)',
                );
                final payload = tab.single['payload'] as Map<String, dynamic>;
                expect(payload, containsPair('thread_item_id', scope));
                expect(
                  DateTime.parse(payload['last_seen_at'] as String).toUtc(),
                  at,
                );
              }
              // Client tests feed exactly this frame.
              final expected = roomSeenReadCursorFrame(
                readerId: readerId,
                beaconId: beaconId,
                at: at,
                event: event,
                threadItemId: scope,
              );
              for (final tab in [real.first, real.second]) {
                expect(
                  {
                    ...tab.single,
                    'payload': _normalised(tab.single['payload'] as Map),
                  },
                  {
                    ...expected,
                    'payload': _normalised(expected['payload'] as Map),
                  },
                );
              }
            }
          }
        },
        skip: skipReason,
      );
    }
  }, skip: skipReason);
}

/// Compares timestamps by instant: Postgres and Dart spell UTC differently.
Map<String, Object?> _normalised(Map<dynamic, dynamic> payload) => {
  for (final MapEntry(:key, :value) in payload.entries)
    key as String: key == 'last_seen_at' && value is String
        ? DateTime.parse(value).toUtc().toIso8601String()
        : value,
};
