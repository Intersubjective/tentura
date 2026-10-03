@Tags(['pg'])
library;

import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Ufirstrespauth1';
const _memberB = 'Ufirstrespmemb1';
const _memberC = 'Ufirstrespmemb2';
const _users = [_author, _memberB, _memberC];

const _post = 'Bfirstresppost01';
const _request = 'Bfirstrespreq001';
const _postRoot = 'Rfirstresppost01';
const _requestRoot = 'Rfirstrespreq001';

const _kindMessage = 1;
const _kindReaction = 2;
const _contactEngaged = 1;
const _eventName = 'postFirstResponse';

/// The first thing a non-author member does in a Post room — a message or a
/// reaction — is claimed exactly once per member. The claim engages the
/// member's inbound contact edge and tells the author with a single
/// `postFirstResponse` receipt; later messages, reactions that are removed and
/// added again, and the author's own activity never produce another one, and a
/// Request room never produces any.
///
/// Real repositories over a disposable Postgres, with real attention dispatch.
/// See `docs/plans/post-and-constellation-composer-plan.md` §4.4.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_FIRST_RESPONSE_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_first_resp',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('First response to a Post', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late Connection writer;
    late BeaconRoomCase room;
    late BeaconRoomRepository roomRepository;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      final built = _buildRoom(database, target.databaseEnv);
      room = built.room;
      roomRepository = built.roomRepository;
    });

    setUp(() async => _seed(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<int> receipts(String accountId) async {
      final rows = await writer.execute('''
SELECT count(*)::int
FROM public.attention_occurrence_recipient r
JOIN public.attention_occurrence o ON o.id = r.occurrence_id
WHERE o.event_type = '$_eventName' AND r.account_id = '$accountId'
''');
      return rows.single.single! as int;
    }

    Future<List<ResultRow>> claims(String beaconId) => writer.execute('''
SELECT user_id, source_kind, source_id
FROM public.post_first_response
WHERE beacon_id = '$beaconId'
ORDER BY user_id
''');

    Future<int?> contactOutcome(String beaconId, String recipientId) async =>
        (await writer.execute('''
SELECT contact_outcome FROM public.beacon_forward_edge
WHERE beacon_id = '$beaconId' AND recipient_id = '$recipientId'
  AND sender_id = '$_author'
''')).single.single
            as int?;

    /// Toggles the 👍 reaction on the room root and reports whether it ended
    /// up added, read from the reaction table.
    Future<bool> react(String userId, {String beaconId = _post}) async {
      final messageId = beaconId == _post ? _postRoot : _requestRoot;
      await room.reactionToggle(
        beaconId: beaconId,
        messageId: messageId,
        userId: userId,
        emoji: '👍',
      );
      final rows = await writer.execute('''
SELECT count(*)::int FROM public.beacon_room_message_reaction
WHERE message_id = '$messageId' AND user_id = '$userId'
''');
      return (rows.single.single! as int) > 0;
    }

    group('by message', () {
      test('records the claim and tells the author once', () async {
        expect(await contactOutcome(_post, _memberB), isNull);

        final message = await room.createMessage(
          beaconId: _post,
          userId: _memberB,
          body: 'Count me in',
        );

        expect(await receipts(_author), 1);
        final rows = await claims(_post);
        expect(rows, hasLength(1));
        expect(rows.single[0], _memberB);
        expect(rows.single[1], _kindMessage);
        expect(rows.single[2], message['id']);
      });

      test("engages the member's inbound contact edge", () async {
        await room.createMessage(
          beaconId: _post,
          userId: _memberB,
          body: 'Count me in',
        );

        expect(await contactOutcome(_post, _memberB), _contactEngaged);
        expect(
          await contactOutcome(_post, _memberC),
          isNull,
          reason: 'only the member who responded is engaged',
        );
      });

      test('a second message from the same member adds nothing', () async {
        final first = await room.createMessage(
          beaconId: _post,
          userId: _memberB,
          body: 'Count me in',
        );
        await room.createMessage(
          beaconId: _post,
          userId: _memberB,
          body: 'And one more thing',
        );

        expect(await receipts(_author), 1);
        final rows = await claims(_post);
        expect(rows, hasLength(1));
        expect(rows.single[2], first['id'], reason: 'the winner is immutable');
      });

      test('another member gets a claim and a receipt of their own', () async {
        await room.createMessage(
          beaconId: _post,
          userId: _memberB,
          body: 'Count me in',
        );
        await room.createMessage(
          beaconId: _post,
          userId: _memberC,
          body: 'Me too',
        );

        expect(await receipts(_author), 2);
        expect((await claims(_post)).map((r) => r[0]), [_memberB, _memberC]);
      });

      test('only the author is told', () async {
        await room.createMessage(
          beaconId: _post,
          userId: _memberB,
          body: 'Count me in',
        );

        expect(await receipts(_memberB), 0);
        expect(await receipts(_memberC), 0);
      });
    });

    group('by reaction', () {
      test('adding a reaction records the claim and tells the author', () async {
        expect(await react(_memberC), isTrue);

        expect(await receipts(_author), 1);
        final rows = await claims(_post);
        expect(rows, hasLength(1));
        expect(rows.single[0], _memberC);
        expect(rows.single[1], _kindReaction);
        expect(rows.single[2], isNotEmpty);
        expect(await contactOutcome(_post, _memberC), _contactEngaged);
      });

      test('removing and adding the reaction again adds nothing', () async {
        await react(_memberC);

        expect(await react(_memberC), isFalse, reason: 'second toggle removes');
        expect(await receipts(_author), 1);
        expect(
          await claims(_post),
          hasLength(1),
          reason: 'removing the reaction does not release the claim',
        );

        expect(await react(_memberC), isTrue, reason: 'third toggle re-adds');
        expect(await receipts(_author), 1);
        expect(await claims(_post), hasLength(1));
      });

      test('removing a reaction alone never claims', () async {
        await writer.execute('''
INSERT INTO public.beacon_room_message_reaction (id, message_id, user_id, emoji)
VALUES ('Efirstresprow001', '$_postRoot', '$_memberC', '👍')
''');

        expect(await react(_memberC), isFalse);

        expect(await claims(_post), isEmpty);
        expect(await receipts(_author), 0);
      });

      test('a reaction followed by a message keeps the reaction claim '
          'and sends one receipt', () async {
        await react(_memberB);
        await room.createMessage(
          beaconId: _post,
          userId: _memberB,
          body: 'Now in words',
        );

        expect(await receipts(_author), 1);
        final rows = await claims(_post);
        expect(rows, hasLength(1));
        expect(rows.single[1], _kindReaction);
      });

      test('a message followed by a reaction keeps the message claim '
          'and sends one receipt', () async {
        await room.createMessage(
          beaconId: _post,
          userId: _memberB,
          body: 'Count me in',
        );
        await react(_memberB);

        expect(await receipts(_author), 1);
        final rows = await claims(_post);
        expect(rows, hasLength(1));
        expect(rows.single[1], _kindMessage);
      });
    });

    group('no claim', () {
      test("the author's own message and reaction", () async {
        await room.createMessage(
          beaconId: _post,
          userId: _author,
          body: 'Anyone there?',
        );
        await react(_author);

        expect(await claims(_post), isEmpty);
        expect(await receipts(_author), 0);
      });

      test('a Request room, by message or by reaction', () async {
        await room.createMessage(
          beaconId: _request,
          userId: _memberB,
          body: 'Happy to help',
        );
        await react(_memberB, beaconId: _request);

        expect(await claims(_request), isEmpty);
        expect(await receipts(_author), 0);
      });
    });

    test('a message and a reaction from the same member at the same time '
        'make exactly one claim, in every round', () async {
      for (var round = 0; round < 10; round++) {
        await _seed(writer);

        await Future.wait([
          room.createMessage(
            beaconId: _post,
            userId: _memberB,
            body: 'Round $round',
          ),
          react(_memberB),
        ]);

        expect(await claims(_post), hasLength(1), reason: 'round $round');
        expect(await receipts(_author), 1, reason: 'round $round');
      }
    });

    group('repository', () {
      test('toggleReaction says whether the reaction was added', () async {
        expect(
          await roomRepository.toggleReaction(
            messageId: _postRoot,
            userId: _memberC,
            emoji: '👍',
          ),
          isTrue,
        );
        expect(
          await roomRepository.toggleReaction(
            messageId: _postRoot,
            userId: _memberC,
            emoji: '👍',
          ),
          isFalse,
        );
      });

      test('claimPostFirstResponse is true once per member of a Post', () async {
        Future<bool> claim(String userId, int kind, [String beaconId = _post]) =>
            roomRepository.claimPostFirstResponse(
              beaconId: beaconId,
              userId: userId,
              kind: kind,
              sourceId: 'source-$userId-$kind',
            );

        expect(await claim(_memberB, _kindMessage), isTrue);
        expect(await claim(_memberB, _kindMessage), isFalse);
        expect(await claim(_memberB, _kindReaction), isFalse);
        expect(await claim(_memberC, _kindReaction), isTrue);
      });

      test('claimPostFirstResponse refuses the author and a Request', () async {
        expect(
          await roomRepository.claimPostFirstResponse(
            beaconId: _post,
            userId: _author,
            kind: _kindMessage,
            sourceId: 'source',
          ),
          isFalse,
        );
        expect(
          await roomRepository.claimPostFirstResponse(
            beaconId: _request,
            userId: _memberB,
            kind: _kindMessage,
            sourceId: 'source',
          ),
          isFalse,
        );
        expect(await claims(_post), isEmpty);
        expect(await claims(_request), isEmpty);
      });
    });
  });
}

({BeaconRoomCase room, BeaconRoomRepository roomRepository}) _buildRoom(
  TenturaDb db,
  Env env,
) {
  final logger = Logger('PostFirstResponsePgTest');
  final uow = MutatingUnitOfWork(db);
  final attention = TransactionalAttentionCase(
    uow,
    AttentionDispatchRepository(db, logger),
  );
  final roomRepository = BeaconRoomRepository(db);
  final blocks = UserBlockRepository(env, db);
  final intents = AttentionIntentCase(
    BeaconRoomNotificationContextRepository(
      roomRepository,
      db,
      HelpOfferRepository(db),
      CommitmentRepository(db),
    ),
    UserRepository(
      env,
      db,
      _UnusedGenealogy(),
      InviteSeedPromptRepositoryMock(),
    ),
    BeaconAccessRepository(db),
    blocks,
  );
  return (
    room: BeaconRoomCase(
      roomRepository,
      CoordinationItemRepository(db),
      _UnusedFactCards(),
      _UnusedImages(),
      _Tasks(),
      _Storage(),
      _UnusedPolling(),
      _Quota(),
      blocks,
      uow,
      BeaconHierarchyRepository(db),
      const ProductionDiscussionProductPolicy(),
      beaconRepository: BeaconRepository(db),
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    ),
    roomRepository: roomRepository,
  );
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.post_first_response,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.inbox_item,
  public.beacon_room_message_reaction,
  public.beacon_room_message,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': _users[i], 'key': pgTestPublicKey('firstresp', i + 1)},
    );
  }
  // The Post: the author forwards it to both members; the forward-edge trigger
  // admits them as addressees.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Ffirstrespedge1', '$_post', '$_author', '$_memberB'),
  ('Ffirstrespedge2', '$_post', '$_author', '$_memberC')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_postRoot', '$_post', '$_author', 'Heads up')
''');
  await writer.execute('''
UPDATE public.beacon SET post_root_message_id = '$_postRoot'
WHERE id = '$_post'
''');
  // A Request with the same people in its room.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Ffirstrespedge3', '$_request', '$_author', '$_memberB')
''');
  await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pfirstrespreqb01', '$_request', '$_memberB', 0, 0, 3)
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_requestRoot', '$_request', '$_author', 'Welcome')
''');
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

final class _UnusedPolling extends Fake implements PollingRepositoryPort {}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task-id';
}

final class _Storage extends Fake implements RemoteStoragePort {
  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    await bytes.drain<void>();
    return path;
  }
}

final class _Quota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async => true;
}
