@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/room_baton_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/room_baton_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/post_write_guard_fixture.dart';

const _post = (beaconId: guardPost, batonId: guardBaton);
const _request = (
  beaconId: 'Bbatonguardrequest',
  batonId: 'Tbatonguardrequest',
);
typedef _Room = ({String beaconId, String batonId});

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BATON_POST_EXPIRY_TEST_DB',
    defaultNamePrefix: 'tentura_test_baton_post_expiry',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late RoomBatonCase baton;
  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    db = openDisposablePgDatabase(target);
    final env = target.databaseEnv;
    final logger = Logger('BatonPostExpiry');
    final room = BeaconRoomRepository(db);
    baton = RoomBatonCase(
      RoomBatonRepository(db),
      room,
      BeaconHierarchyRepository(db),
      PostLockRepository(db),
      TransactionalAttentionCase(
        MutatingUnitOfWork(db),
        AttentionDispatchRepository(db, logger),
      ),
      AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          room,
          db,
          HelpOfferRepository(db),
          CommitmentRepository(db),
        ),
        UserRepository(env, db, _Genealogy(), InviteSeedPromptRepositoryMock()),
        BeaconAccessRepository(db),
        FakeUserBlockRepository(),
      ),
      env: env,
      logger: logger,
    );
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  final operations = <String, Future<void> Function(_Room)>{
    'create': (room) async {
      await baton.create(
        actorId: guardAuthor,
        beaconId: room.beaconId,
        text: 'Please help',
        candidates: [(userId: guardMember, tier: 1)],
      );
    },
    'update': (room) => baton.update(
      actorId: guardAuthor,
      batonId: room.batonId,
      text: 'Updated ask',
      candidates: [(userId: guardMember, tier: 2)],
    ),
    'respond': (room) => baton.respond(
      actorId: guardMember,
      batonId: room.batonId,
      canHelp: false,
    ),
    'select': (room) => baton.select(
      actorId: guardAuthor,
      batonId: room.batonId,
      userId: guardMember,
    ),
    'cancel': (room) =>
        baton.cancel(actorId: guardAuthor, batonId: room.batonId),
  };

  for (final entry in operations.entries) {
    for (final state in ['closed', 'expired']) {
      test(
        '${state == 'expired' ? 'An' : 'A'} $state Post rejects baton ${entry.key} as read-only',
        () async {
          await _seed(writer);
          await archiveGuardPost(writer, state);
          final before = await _snapshot(writer);
          await expectLater(
            entry.value(_post),
            throwsA(
              isA<BeaconCreateException>().having(
                (e) => e.description,
                'description',
                'Discussion is read-only for this request',
              ),
            ),
          );
          expect(await _snapshot(writer), before);
        },
      );
    }
    for (final (label, room) in [
      ('open Post', _post),
      ('open Request', _request),
    ]) {
      test('an $label permits baton ${entry.key}', () async {
        await _seed(writer);
        if (room == _request) await _seedRequest(writer);
        await entry.value(room);
        await _expectOperationResult(writer, entry.key, room);
      });
    }
  }
}

Future<void> _expectOperationResult(
  Connection writer,
  String operation,
  _Room room,
) async {
  final beaconId = room.beaconId;
  final batonId = room.batonId;
  switch (operation) {
    case 'create':
      final rows = await writer.execute("""
SELECT b.beacon_id, b.author_id, b.status, m.body, c.user_id, c.tier, c.response
FROM public.beacon_room_baton b
JOIN public.beacon_room_message m ON m.id = b.message_id
JOIN public.beacon_room_baton_candidate c ON c.baton_id = b.id
WHERE b.beacon_id = '$beaconId' AND b.id <> '$batonId'
""");
      expect(rows.map((row) => row.toList()).toList(), [
        [beaconId, guardAuthor, 0, 'Please help', guardMember, 1, 0],
      ]);
    case 'update':
      final rows = await writer.execute("""
SELECT b.status, m.body, c.user_id, c.tier, c.response
FROM public.beacon_room_baton b
JOIN public.beacon_room_message m ON m.id = b.message_id
JOIN public.beacon_room_baton_candidate c ON c.baton_id = b.id
WHERE b.id = '$batonId' AND b.beacon_id = '$beaconId'
""");
      expect(rows.map((row) => row.toList()).toList(), [
        [0, 'Updated ask', guardMember, 2, 1],
      ]);
    case 'respond':
      final rows = await writer.execute("""
SELECT response, responded_at IS NOT NULL
FROM public.beacon_room_baton_candidate c
JOIN public.beacon_room_baton b ON b.id = c.baton_id
WHERE c.baton_id = '$batonId' AND b.beacon_id = '$beaconId' AND c.user_id = '$guardMember'
""");
      expect(rows.single.toList(), [2, true]);
    case 'select':
      final rows = await writer.execute("""
SELECT status, taker_id, selection_mode, resolved_at IS NOT NULL
FROM public.beacon_room_baton WHERE id = '$batonId' AND beacon_id = '$beaconId'
""");
      expect(rows.single.toList(), [1, guardMember, 2, true]);
    case 'cancel':
      final rows = await writer.execute("""
SELECT status, resolved_at IS NOT NULL
FROM public.beacon_room_baton WHERE id = '$batonId' AND beacon_id = '$beaconId'
""");
      expect(rows.single.toList(), [2, true]);
    default:
      throw ArgumentError.value(operation);
  }
}

Future<void> _seed(Connection writer) async {
  await seedPostWriteGuard(writer);
  await writer.execute('''
INSERT INTO public.beacon_participant (id, beacon_id, user_id, role, status, room_access)
SELECT 'Pbatonguardmember', '$guardPost', '$guardMember', 0, 0, 3
WHERE NOT EXISTS (SELECT 1 FROM public.beacon_participant WHERE beacon_id = '$guardPost' AND user_id = '$guardMember')
''');
  await writer.execute(
    "UPDATE public.beacon_participant SET room_access = 3 WHERE beacon_id = '$guardPost' AND user_id = '$guardMember'",
  );
  await writer.execute('''
INSERT INTO public.beacon_room_baton_candidate (baton_id, user_id, tier, response, responded_at)
VALUES ('$guardBaton', '$guardMember', 1, 1, now())
''');
}

Future<void> _seedRequest(Connection writer) async {
  await writer.execute("""
INSERT INTO public.beacon (id, user_id, title, description, status, kind, published_at)
VALUES ('${_request.beaconId}', '$guardAuthor', 'Request', '', 0, 0, now())
""");
  await writer.execute("""
INSERT INTO public.beacon_participant (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pbatonguardrequest', '${_request.beaconId}', '$guardMember', 0, 0, 3)
""");
  await writer.execute("""
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('Rbatonguardrequest', '${_request.beaconId}', '$guardAuthor', 'Take it')
""");
  await writer.execute("""
INSERT INTO public.beacon_room_baton (id, message_id, beacon_id, author_id)
VALUES ('${_request.batonId}', 'Rbatonguardrequest', '${_request.beaconId}', '$guardAuthor')
""");
  await writer.execute("""
INSERT INTO public.beacon_room_baton_candidate (baton_id, user_id, tier, response, responded_at)
VALUES ('${_request.batonId}', '$guardMember', 1, 1, now())
""");
}

Future<String> _snapshot(Connection writer) async {
  final rows = await writer.execute('''
SELECT
  (SELECT json_agg(b ORDER BY b.id)::text FROM public.beacon_room_baton b),
  (SELECT json_agg(c ORDER BY c.baton_id, c.user_id)::text FROM public.beacon_room_baton_candidate c),
  (SELECT json_agg(m ORDER BY m.id)::text FROM public.beacon_room_message m),
  (SELECT count(*) FROM public.attention_occurrence)
''');
  return rows.single.join('|');
}

final class _Genealogy extends Fake implements InviteGenealogyRepositoryPort {}
