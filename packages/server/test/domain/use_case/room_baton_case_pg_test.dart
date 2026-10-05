@Tags(['pg'])
library;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
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
import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/room_baton_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Ubatoncase_au1';
const _candA = 'Ubatoncase_ca1';
const _candB = 'Ubatoncase_cb1';
const _member = 'Ubatoncase_mb1';
const _outsider = 'Ubatoncase_ou1';

const _request = 'Bbatoncase_rq1';
const _post = 'Bbatoncase_ps1';
const _requestMessage = 'Rbatoncase_rq1';
const _postMessage = 'Rbatoncase_ps1';
const _foreignMessage = 'Rbatoncase_fo1';
const _pollMessage = 'Rbatoncase_pl1';
const _systemMessage = 'Rbatoncase_sy1';
const _noticeMessage = 'Rbatoncase_nt1';
const _threadMessage = 'Rbatoncase_th1';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_BATON_CASE_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_baton_case',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('RoomBatonCase.create / respond', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late RoomBatonCase batonCase;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      batonCase = _buildCase(database, target.databaseEnv);
    });

    setUp(() => _resetFixture(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<RoomBaton> createOnRequest({
      List<({String userId, int tier})>? candidates,
    }) => batonCase.create(
      actorId: _author,
      messageId: _requestMessage,
      candidates: candidates ?? [(userId: _candA, tier: 1), (userId: _candB, tier: 2)],
    );

    test('create on own message stores the baton and its candidates', () async {
      final baton = await createOnRequest();

      expect(baton.status, BatonStatus.collecting);
      expect(baton.authorId, _author);
      expect(baton.messageId, _requestMessage);
      expect(baton.beaconId, _request);
      expect(await _count(writer, 'beacon_room_baton'), 1);
      expect(await _count(writer, 'beacon_room_baton_candidate'), 2);
      final tiers = await writer.execute('''
SELECT user_id, tier, response FROM public.beacon_room_baton_candidate
ORDER BY user_id
''');
      expect(
        tiers.map((r) => [r[0], r[1], r[2]]).toList(),
        [
          [_candA, 1, 0],
          [_candB, 2, 0],
        ],
      );
    });

    test('create sends exactly one batonAsked receipt per candidate', () async {
      await createOnRequest();

      expect(
        await _receiptRecipients(writer, 'batonAsked'),
        [_candA, _candB],
        reason: 'one receipt per candidate; none for the author or members',
      );
      expect(await _count(writer, 'notification_outbox'), 2);
      expect(await _count(writer, 'attention_occurrence'), 2);
    });

    test('batonAsked receipts never carry another candidate id', () async {
      await createOnRequest();

      for (final (recipient, other) in [(_candA, _candB), (_candB, _candA)]) {
        final blob = await _receiptBlob(writer, 'batonAsked', recipient);
        expect(blob, isNotEmpty);
        expect(blob, isNot(contains(other)));
      }
    });

    test('create on a message in a Post room works', () async {
      final baton = await batonCase.create(
        actorId: _author,
        messageId: _postMessage,
        candidates: [(userId: _candA, tier: 1)],
      );

      expect(baton.beaconId, _post);
      expect(await _receiptRecipients(writer, 'batonAsked'), [_candA]);
    });

    for (final (beaconId, messageId) in [
      (_request, _requestMessage),
      (_post, _postMessage),
    ]) {
      test('author without participant row can create on $beaconId', () async {
        await writer.execute('''
DELETE FROM public.beacon_participant
WHERE beacon_id = '$beaconId' AND user_id = '$_author'
''');

        final baton = await batonCase.create(
          actorId: _author,
          messageId: messageId,
          candidates: [(userId: _candA, tier: 1)],
        );

        expect(baton.beaconId, beaconId);
        expect(baton.authorId, _author);
        expect(baton.status, BatonStatus.collecting);
        expect(await _receiptRecipients(writer, 'batonAsked'), [_candA]);
      });
    }

    test('create on someone else\'s message is rejected without rows', () async {
      await expectLater(
        batonCase.create(
          actorId: _author,
          messageId: _foreignMessage,
          candidates: [(userId: _candA, tier: 1)],
        ),
        throwsA(isA<BatonMessageNotEligibleException>()),
      );
      await _expectNothingWritten(writer);
    });

    test('create on a poll message is rejected without rows', () async {
      await expectLater(
        batonCase.create(
          actorId: _author,
          messageId: _pollMessage,
          candidates: [(userId: _candA, tier: 1)],
        ),
        throwsA(isA<BatonMessageNotEligibleException>()),
      );
      await _expectNothingWritten(writer);
    });

    test('create on a system message is rejected without rows', () async {
      await expectLater(
        batonCase.create(
          actorId: _author,
          messageId: _systemMessage,
          candidates: [(userId: _candA, tier: 1)],
        ),
        throwsA(isA<BatonMessageNotEligibleException>()),
      );
      await _expectNothingWritten(writer);
    });

    test('create on a system-notice message is rejected without rows', () async {
      await expectLater(
        batonCase.create(
          actorId: _author,
          messageId: _noticeMessage,
          candidates: [(userId: _candA, tier: 1)],
        ),
        throwsA(isA<BatonMessageNotEligibleException>()),
      );
      await _expectNothingWritten(writer);
    });

    test('create on a message outside the General room is rejected without rows',
        () async {
      await expectLater(
        batonCase.create(
          actorId: _author,
          messageId: _threadMessage,
          candidates: [(userId: _candA, tier: 1)],
        ),
        throwsA(isA<BatonMessageNotEligibleException>()),
      );
      await _expectNothingWritten(writer);
    });

    test('create with the author as a candidate is rejected', () async {
      await expectLater(
        createOnRequest(candidates: [(userId: _author, tier: 1)]),
        throwsA(isA<BatonInvalidCandidatesException>()),
      );
      await _expectNothingWritten(writer);
    });

    test('create with a non-admitted candidate is rejected', () async {
      await expectLater(
        createOnRequest(
          candidates: [(userId: _candA, tier: 1), (userId: _outsider, tier: 1)],
        ),
        throwsA(isA<BatonInvalidCandidatesException>()),
      );
      await _expectNothingWritten(writer);
    });

    test('a second baton on the same message is rejected', () async {
      await createOnRequest();
      final receiptsBefore = await _receiptRecipients(writer, 'batonAsked');

      await expectLater(
        createOnRequest(candidates: [(userId: _member, tier: 1)]),
        throwsA(isA<BatonAlreadyActiveException>()),
      );

      expect(await _count(writer, 'beacon_room_baton'), 1);
      expect(await _count(writer, 'beacon_room_baton_candidate'), 2);
      expect(await _receiptRecipients(writer, 'batonAsked'), receiptsBefore);
    });

    test('create in a closed room is rejected like posting a message',
        () async {
      await writer.execute('''
UPDATE public.beacon SET status = ${BeaconStatus.closed.smallintValue}
WHERE id = '$_request'
''');

      await expectLater(
        createOnRequest(),
        throwsA(isA<BeaconCreateException>()),
        reason: 'same rejection as posting a message in a read-only room',
      );
      await _expectNothingWritten(writer);
    });

    test('respond by a non-candidate is rejected', () async {
      final baton = await createOnRequest();

      await expectLater(
        batonCase.respond(actorId: _member, batonId: baton.id, canHelp: true),
        throwsA(isA<BatonNotCandidateException>()),
      );
      expect(await _responses(writer), {_candA: 0, _candB: 0});
    });

    test('a candidate can switch from can-help to cannot-help', () async {
      final baton = await createOnRequest();

      await batonCase.respond(actorId: _candA, batonId: baton.id, canHelp: true);
      expect((await _responses(writer))[_candA], 1);

      await batonCase.respond(
        actorId: _candA,
        batonId: baton.id,
        canHelp: false,
      );
      expect((await _responses(writer))[_candA], 2);
      final respondedAt = await writer.execute('''
SELECT responded_at FROM public.beacon_room_baton_candidate
WHERE user_id = '$_candA'
''');
      expect(respondedAt.single[0], isNotNull);
    });

    test('switching an answer that completes the set notifies the author once',
        () async {
      final baton = await createOnRequest();
      await batonCase.respond(actorId: _candA, batonId: baton.id, canHelp: true);
      await batonCase.respond(actorId: _candB, batonId: baton.id, canHelp: true);
      expect(await _receiptRecipients(writer, 'batonAllAnswered'), [_author]);

      await batonCase.respond(
        actorId: _candB,
        batonId: baton.id,
        canHelp: false,
      );

      expect((await _responses(writer))[_candB], 2);
      expect(await _receiptRecipients(writer, 'batonAllAnswered'), [_author]);
    });

    for (final (label, setStatus) in [
      (
        'taken',
        "status = 1, selection_mode = 1, resolved_at = now(), taker_id = '$_candA'",
      ),
      ('cancelled', 'status = 2, resolved_at = now()'),
    ]) {
      test('respond on a $label baton is rejected and changes nothing',
          () async {
        final baton = await createOnRequest();
        await writer.execute(
          'UPDATE public.beacon_room_baton SET $setStatus',
        );

        await expectLater(
          batonCase.respond(actorId: _candB, batonId: baton.id, canHelp: true),
          throwsA(isA<BatonNotCollectingException>()),
        );

        expect(await _responses(writer), {_candA: 0, _candB: 0});
        expect(await _receiptRecipients(writer, 'batonAllAnswered'), isEmpty);
      });
    }

    test('a candidate who lost room admission cannot respond', () async {
      final baton = await createOnRequest();
      await writer.execute('''
UPDATE public.beacon_participant SET room_access = 0
WHERE beacon_id = '$_request' AND user_id = '$_candB'
''');

      await expectLater(
        batonCase.respond(actorId: _candB, batonId: baton.id, canHelp: true),
        throwsA(isA<BatonNotCandidateException>()),
      );

      expect(await _responses(writer), {_candA: 0, _candB: 0});
      expect(await _receiptRecipients(writer, 'batonAllAnswered'), isEmpty);
    });

    test('the last answer notifies the author exactly once', () async {
      final baton = await createOnRequest();

      await batonCase.respond(actorId: _candA, batonId: baton.id, canHelp: true);
      expect(await _receiptRecipients(writer, 'batonAllAnswered'), isEmpty);

      await batonCase.respond(
        actorId: _candB,
        batonId: baton.id,
        canHelp: false,
      );
      expect(await _receiptRecipients(writer, 'batonAllAnswered'), [_author]);

      // Changing an answer afterwards must not notify again.
      await batonCase.respond(
        actorId: _candA,
        batonId: baton.id,
        canHelp: false,
      );
      await batonCase.respond(actorId: _candB, batonId: baton.id, canHelp: true);
      expect(await _receiptRecipients(writer, 'batonAllAnswered'), [_author]);
      final stamp = await writer.execute(
        'SELECT all_answered_notified_at FROM public.beacon_room_baton',
      );
      expect(stamp.single[0], isNotNull);
    });

    test('concurrent final answers notify the author exactly once', () async {
      for (var round = 0; round < 10; round++) {
        await _resetFixture(writer);
        final baton = await createOnRequest();

        await Future.wait([
          batonCase.respond(actorId: _candA, batonId: baton.id, canHelp: true),
          batonCase.respond(actorId: _candB, batonId: baton.id, canHelp: false),
        ]);

        expect(
          await _receiptRecipients(writer, 'batonAllAnswered'),
          [_author],
          reason: 'round $round',
        );
        expect(
          await _count(writer, 'notification_outbox'),
          2 + 1,
          reason: 'round $round: two batonAsked plus one batonAllAnswered',
        );
      }
    });
  });
}

RoomBatonCase _buildCase(TenturaDb db, Env env) {
  final logger = Logger('RoomBatonCasePgTest');
  final room = BeaconRoomRepository(db);
  final attention = TransactionalAttentionCase(
    MutatingUnitOfWork(db),
    AttentionDispatchRepository(db, logger),
  );
  final attentionIntents = AttentionIntentCase(
    BeaconRoomNotificationContextRepository(
      room,
      db,
      HelpOfferRepository(db),
      CommitmentRepository(db),
    ),
    UserRepository(
      env,
      db,
      _NoopInviteGenealogyRepository(),
      InviteSeedPromptRepositoryMock(),
    ),
    BeaconAccessRepository(db),
    FakeUserBlockRepository(),
  );
  return RoomBatonCase(
    RoomBatonRepository(db),
    room,
    BeaconHierarchyRepository(db),
    PostLockRepository(db),
    attention,
    attentionIntents,
    env: env,
    logger: logger,
  );
}

Future<int> _count(Connection writer, String table) async {
  final rows = await writer.execute('SELECT count(*) FROM public.$table');
  return rows.single[0]! as int;
}

Future<void> _expectNothingWritten(Connection writer) async {
  expect(await _count(writer, 'beacon_room_baton'), 0);
  expect(await _count(writer, 'beacon_room_baton_candidate'), 0);
  expect(await _receiptRecipients(writer, 'batonAsked'), isEmpty);
  expect(await _receiptRecipients(writer, 'batonAllAnswered'), isEmpty);
}

Future<Map<String, int>> _responses(Connection writer) async {
  final rows = await writer.execute(
    'SELECT user_id, response FROM public.beacon_room_baton_candidate',
  );
  return {for (final r in rows) r[0]! as String: r[1]! as int};
}

Future<List<String>> _receiptRecipients(
  Connection writer,
  String eventType,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT outbox.account_id
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE occ.event_type = @type
ORDER BY outbox.account_id
'''),
    parameters: {'type': eventType},
  );
  return rows.map((r) => r[0]! as String).toList();
}

/// Everything persisted for one recipient's receipt, as text.
Future<String> _receiptBlob(
  Connection writer,
  String eventType,
  String recipient,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT row_to_json(outbox)::text || row_to_json(occ)::text
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE occ.event_type = @type AND outbox.account_id = @recipient
'''),
    parameters: {'type': eventType, 'recipient': recipient},
  );
  return rows.map((r) => r[0]! as String).join();
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_room_baton_candidate,
  public.beacon_room_baton,
  public.beacon_room_message,
  public.polling,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_author, _candA, _candB, _member, _outsider];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('batoncase', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
  var n = 0;
  for (final beacon in [_request, _post]) {
    for (final user in [_author, _candA, _candB, _member]) {
      await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pbatoncase${(n++).toString().padLeft(3, '0')}', '$beacon', '$user', 0, 0, 3)
''');
    }
  }
  await writer.execute('''
INSERT INTO public.polling (id, author_id, question)
VALUES ('Zbatoncase_pl1', '$_author', 'Which day?')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES
  ('$_requestMessage', '$_request', '$_author', 'Can someone take this?'),
  ('$_postMessage', '$_post', '$_author', 'Can someone take this?'),
  ('$_foreignMessage', '$_request', '$_member', 'Someone else wrote this')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, linked_polling_id)
VALUES ('$_pollMessage', '$_request', '$_author', 'Poll', 'Zbatoncase_pl1')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, system_message_kind)
VALUES ('$_noticeMessage', '$_request', '$_author', 'Notice', 1)
''');
  await writer.execute('''
INSERT INTO public.coordination_item (id, beacon_id, kind, creator_id)
VALUES ('Ithread000001', '$_request', 0, '$_author')
''');
  await writer.execute(
    "SET tentura.discussion_internal_fixture = 'allow_non_general'",
  );
  try {
    await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, thread_item_id)
VALUES ('$_threadMessage', '$_request', '$_author', 'Threaded', 'Ithread000001')
''');
  } finally {
    await writer.execute('RESET tentura.discussion_internal_fixture');
  }
  await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, semantic_marker)
VALUES ('$_systemMessage', '$_request', '$_author', 'Marker', 1)
''');
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
