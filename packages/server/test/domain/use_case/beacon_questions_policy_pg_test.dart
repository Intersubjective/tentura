@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/entity/questions_access.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_lobby_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/room_message_snapshot_lookup.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';

class _FakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _FakeImages extends Fake implements ImageRepositoryPort {}

class _FakeTasks extends Fake implements TaskRepositoryPort {}

class _FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class _FakePolling extends Fake implements PollingRepositoryPort {}

class _FakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {}

/// Records whom each directed room notice (which carries the message text)
/// would reach.
final class _RecordingIntents extends Fake implements AttentionIntentCase {
  final mentioned = <String>{};
  final directed = <String>{};

  static const _intent = AttentionDispatchIntent(
    eventType: AttentionEventType.relayReceived,
    sourceEventKey: 'test',
    actorUserId: null,
    priority: NotificationPriority.high,
    kind: NotificationKind.needsMe,
    title: '',
    body: '',
    actionUrl: '',
    collapseKey: '',
    recipients: [],
  );

  void clear() {
    mentioned.clear();
    directed.clear();
  }

  @override
  Future<AttentionDispatchIntent> roomMentioned({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required Set<String> recipientUserIds,
    required String excerpt,
    required String sourceEventKey,
    String? threadItemId,
    bool questionsScope = false,
  }) async {
    expect(questionsScope, isTrue);
    mentioned.addAll(recipientUserIds);
    return _intent;
  }

  @override
  Future<AttentionDispatchIntent> roomMessagePosted({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required Set<String> recipientUserIds,
    required String excerpt,
    required String sourceEventKey,
    String? threadItemId,
    bool questionsScope = false,
  }) async {
    expect(questionsScope, isTrue);
    directed.addAll(recipientUserIds);
    return _intent;
  }
}

final class _NoopDispatch implements AttentionDispatchPort {
  @override
  Future<void> record(AttentionDispatchIntent intent) async {}
}

/// One audience class of the Questions policy matrix.
typedef _Case = ({String name, String id, QuestionsAccess expected});

/// Request **Questions** (internally the Request lobby, U088 / #526, sprint
/// decision D1, owner answers Q2–Q4): ONE server-owned policy
/// (`questions_access_levels`, m0254) for open, read, history, post, edit,
/// delete, react, seen, mentions, notifications and realtime.
///
/// Matrix: each audience class × each operation, plus rejected / cancelled
/// forwards, a departed helper, a steward, a discovery-only reader, blocks
/// both ways (with the author and between recipients), a ban, a closed
/// Request, and the General-only features that must never reference a
/// Questions message.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_QUESTIONS_TEST_DB',
    defaultNamePrefix: 'tentura_test_beacon_questions',
  );
  final skipReason = await pgSkipReason(target);

  const beaconId = 'Bquestions01';
  const postId = 'Bquestpost01';

  // Write standing.
  const author = 'Uqauthor0001';
  const steward = 'Uqsteward001';
  const forwardee = 'Uqforward001';
  const addressee = 'Uqaddress001';
  const helper = 'Uqhelper0001';
  const offerer = 'Uqofferer001';
  // Read-only standing (Q4).
  const rejected = 'Uqreject0001';
  const departed = 'Uqdepart0001';
  // Direct addressee (role 6) who answered "Can't help".
  const rejectedAddressee = 'Uqrejadd0001';
  // No standing.
  const cancelled = 'Uqcancel0001';
  const discovery = 'Uqdiscov0001';
  const banned = 'Uqbanned0001';
  const blocksAuthor = 'Uqblocks0001';
  const blockedByAuthor = 'Uqblockd0001';
  // Cross-recipient block: peer blocked forwardee.
  const peer = 'Uqpeer000001';

  const matrix = <_Case>[
    (name: 'author', id: author, expected: QuestionsAccess.write),
    (name: 'steward', id: steward, expected: QuestionsAccess.write),
    (name: 'live forward', id: forwardee, expected: QuestionsAccess.write),
    (name: 'direct addressee', id: addressee, expected: QuestionsAccess.write),
    (name: 'admitted helper', id: helper, expected: QuestionsAccess.write),
    (name: 'live offer only', id: offerer, expected: QuestionsAccess.write),
    (name: "answered Can't help", id: rejected, expected: QuestionsAccess.read),
    (name: 'departed helper', id: departed, expected: QuestionsAccess.read),
    (
      name: "addressee who answered Can't help",
      id: rejectedAddressee,
      expected: QuestionsAccess.read,
    ),
    (name: 'cancelled forward', id: cancelled, expected: QuestionsAccess.none),
    (name: 'discovery-only', id: discovery, expected: QuestionsAccess.none),
    (name: 'banned', id: banned, expected: QuestionsAccess.none),
    (name: 'blocked the author', id: blocksAuthor, expected: QuestionsAccess.none),
    (
      name: 'blocked by the author',
      id: blockedByAuthor,
      expected: QuestionsAccess.none,
    ),
  ];

  group('Request Questions policy', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late BeaconRoomRepository room;
    late BeaconLobbyRepository lobby;
    late FakeUserBlockRepository blocks;
    late _RecordingIntents intents;
    late BeaconRoomCase rooms;

    BeaconRoomCase buildRooms({FakeBeaconHierarchyRepository? hierarchy}) =>
        BeaconRoomCase(
          room,
          CoordinationItemRepository(db),
          _FakeFactCards(),
          _FakeImages(),
          _FakeTasks(),
          _FakeRemoteStorage(),
          _FakePolling(),
          _FakeUploadQuota(),
          blocks,
          PassThroughMutatingUnitOfWork(),
          hierarchy ?? FakeBeaconHierarchyRepository(),
          const ProductionDiscussionProductPolicy(),
          attentionIntents: intents,
          attention: TransactionalAttentionCase(
            PassThroughMutatingUnitOfWork(),
            _NoopDispatch(),
          ),
          lobby: lobby,
          env: Env(environment: Environment.test),
          logger: Logger('beacon_questions_policy_pg_test'),
        );

    Future<void> sql(String statement) => writer.execute(statement);

    Future<void> forward(
      String to, {
      bool rejectedEdge = false,
      bool cancelledEdge = false,
      String beacon = beaconId,
    }) => sql(
      'INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, '
      'recipient_id, recipient_rejected, cancelled_at) VALUES '
      "('$beacon', '$author', '$to', $rejectedEdge, "
      "${cancelledEdge ? 'now()' : 'NULL'})",
    );

    Future<void> offer(String userId, {int status = 0}) => sql(
      'INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, '
      "status) VALUES ('$beaconId', '$userId', 'I can help', $status) "
      'ON CONFLICT (beacon_id, user_id) DO UPDATE SET status = '
      'EXCLUDED.status',
    );

    Future<void> participant(
      String userId, {
      int role = 2,
      int roomAccess = 0,
    }) => sql(
      'INSERT INTO public.beacon_participant (beacon_id, user_id, role, '
      "status, room_access) VALUES ('$beaconId', '$userId', $role, 0, "
      '$roomAccess)',
    );

    Future<void> block(String blocker, String blocked) async {
      await sql(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        "VALUES ('$blocker', '$blocked', '$blocker')",
      );
      blocks.blockPair(blocker, blocked);
    }

    Future<String> openAsAuthor() async =>
        (await rooms.beaconLobby(beaconId: beaconId, userId: author))['lobbyId']!
            as String;

    /// Inserts a Questions message as [userId] directly (an earlier message,
    /// written while they still had standing).
    Future<String> seedMessage(String userId, String lobbyId, String body) async {
      final id = 'Mq${userId.substring(2, 10)}${body.length}';
      final escaped = body.replaceAll("'", "''");
      await sql(
        'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, '
        "body, thread_item_id) VALUES ('$id', '$beaconId', '$userId', "
        "'$escaped', '$lobbyId')",
      );
      return id;
    }

    Future<List<String>> bodiesFor(String viewer, String lobbyId) async => [
      for (final r in await rooms.listMessages(
        beaconId: beaconId,
        userId: viewer,
        threadItemId: lobbyId,
      ))
        r['body']! as String,
    ];

    setUpAll(() async {
      if (skipReason != null) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = TenturaDb(target.databaseEnv);
      room = BeaconRoomRepository(db);
      lobby = BeaconLobbyRepository(db);
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      if (skipReason != null) return;
      blocks = FakeUserBlockRepository();
      intents = _RecordingIntents();
      rooms = buildRooms();
      await sql(
        'TRUNCATE TABLE public.beacon_room_message, public.beacon_room_seen, '
        'public.coordination_item, public.beacon_help_offer, '
        'public.beacon_forward_edge, public.beacon_participant, '
        'public.beacon_steward, public.beacon_lobby_ban, public.user_block, '
        'public.beacon, public."user" CASCADE',
      );
      final users = [
        author,
        steward,
        forwardee,
        addressee,
        helper,
        offerer,
        rejected,
        departed,
        rejectedAddressee,
        cancelled,
        discovery,
        banned,
        blocksAuthor,
        blockedByAuthor,
        peer,
      ];
      await sql(
        'INSERT INTO public."user" (id, display_name, handle, public_key) '
        'VALUES ${[for (final u in users) "('$u', '${u.substring(2, 8)}', '${u.substring(2, 8)}', 'k$u')"].join(', ')}',
      );
      await sql(
        'INSERT INTO public.beacon (id, user_id, title, description, status, '
        'kind, is_discoverable, published_at, created_at, updated_at) VALUES '
        "('$beaconId', '$author', 'Moving day', 'desc', 0, 0, true, "
        "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z'), "
        "('$postId', '$author', '', '', 0, 1, false, "
        "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z')",
      );
      await sql(
        'INSERT INTO public.beacon_steward (beacon_id, user_id) VALUES '
        "('$beaconId', '$steward')",
      );
      // A steward also carries participant role 1 (the content gate reads it).
      await participant(steward, role: 1);
      await forward(forwardee);
      await forward(addressee);
      await participant(addressee, role: 6);
      await forward(helper);
      await offer(helper);
      await participant(helper, roomAccess: 3);
      await offer(offerer);
      await forward(rejected, rejectedEdge: true);
      // Departed helper: came by forward, offered, was admitted, withdrew.
      await forward(departed);
      await offer(departed, status: 1);
      await participant(departed, roomAccess: 5);
      await forward(rejectedAddressee, rejectedEdge: true);
      await participant(rejectedAddressee, role: 6);
      await forward(cancelled, cancelledEdge: true);
      // Discovery-only: the Request is discoverable, but nobody sent it.
      await forward(banned);
      await sql(
        'INSERT INTO public.beacon_lobby_ban (beacon_id, user_id, banned_by) '
        "VALUES ('$beaconId', '$banned', '$author')",
      );
      await forward(blocksAuthor);
      await block(blocksAuthor, author);
      await forward(blockedByAuthor);
      await block(author, blockedByAuthor);
      await forward(peer);
      await block(peer, forwardee);
    });

    test('the policy level of every audience class (one set query)', () async {
      final levels = await lobby.accessLevels(
        beaconId: beaconId,
        userIds: [for (final c in matrix) c.id],
      );
      for (final c in matrix) {
        expect(levels[c.id], c.expected, reason: c.name);
      }
    });

    test('a Post has no Questions for anyone', () async {
      final levels = await lobby.accessLevels(
        beaconId: postId,
        userIds: [author, forwardee],
      );
      expect(levels.values, everyElement(QuestionsAccess.none));
      await expectLater(
        rooms.beaconLobby(beaconId: postId, userId: author),
        throwsA(isA<Exception>()),
      );
    });

    test('open and the entry-row probe follow the policy', () async {
      await openAsAuthor();
      for (final c in matrix) {
        final probe = await rooms.beaconLobbyAccess(
          beaconId: beaconId,
          userId: c.id,
        );
        expect(probe['canRead'], c.expected.canRead, reason: c.name);
        expect(probe['canPost'], c.expected.canWrite, reason: c.name);
        if (c.expected.canRead) {
          final opened = await rooms.beaconLobby(
            beaconId: beaconId,
            userId: c.id,
          );
          expect(opened['canPost'], c.expected.canWrite, reason: c.name);
          expect(opened['isAuthor'], c.id == author, reason: c.name);
        } else {
          await expectLater(
            rooms.beaconLobby(beaconId: beaconId, userId: c.id),
            throwsA(isA<BeaconLobbyAccessException>()),
            reason: c.name,
          );
        }
      }
    });

    test('read, history and seen: everyone who may read, nobody else', () async {
      final lobbyId = await openAsAuthor();
      await rooms.createMessage(
        beaconId: beaconId,
        userId: author,
        body: 'Saturday the 18th',
        threadItemId: lobbyId,
      );
      for (final c in matrix) {
        if (c.expected.canRead) {
          expect(
            await bodiesFor(c.id, lobbyId),
            contains('Saturday the 18th'),
            reason: c.name,
          );
          final older = await rooms.listMessages(
            beaconId: beaconId,
            userId: c.id,
            threadItemId: lobbyId,
            beforeIso: '2100-01-01T00:00:00Z',
          );
          expect(older, hasLength(1), reason: c.name);
          await rooms.markThreadSeen(
            beaconId: beaconId,
            userId: c.id,
            threadId: lobbyId,
          );
        } else {
          await expectLater(
            bodiesFor(c.id, lobbyId),
            throwsA(isA<UnauthorizedException>()),
            reason: c.name,
          );
          await expectLater(
            rooms.markThreadSeen(
              beaconId: beaconId,
              userId: c.id,
              threadId: lobbyId,
            ),
            throwsA(isA<UnauthorizedException>()),
            reason: c.name,
          );
        }
      }
    });

    test('post, react, edit and delete: write standing only', () async {
      final lobbyId = await openAsAuthor();
      final authorMessage = await rooms.createMessage(
        beaconId: beaconId,
        userId: author,
        body: 'Ask me anything',
        threadItemId: lobbyId,
      );
      for (final c in matrix) {
        final own = await seedMessage(c.id, lobbyId, 'earlier ${c.name}');
        if (c.expected.canWrite) {
          await rooms.createMessage(
            beaconId: beaconId,
            userId: c.id,
            body: 'question from ${c.name}',
            threadItemId: lobbyId,
          );
          await rooms.reactionToggle(
            beaconId: beaconId,
            messageId: authorMessage['id']! as String,
            userId: c.id,
            emoji: '👍',
          );
          expect(
            await rooms.editMessage(
              beaconId: beaconId,
              messageId: own,
              userId: c.id,
              newBody: 'edited ${c.name}',
            ),
            isTrue,
            reason: c.name,
          );
          expect(
            await rooms.deleteMessage(
              beaconId: beaconId,
              messageId: own,
              userId: c.id,
            ),
            isTrue,
            reason: c.name,
          );
        } else {
          await expectLater(
            rooms.createMessage(
              beaconId: beaconId,
              userId: c.id,
              body: 'question from ${c.name}',
              threadItemId: lobbyId,
            ),
            throwsA(isA<UnauthorizedException>()),
            reason: c.name,
          );
          await expectLater(
            rooms.reactionToggle(
              beaconId: beaconId,
              messageId: authorMessage['id']! as String,
              userId: c.id,
              emoji: '👍',
            ),
            throwsA(isA<UnauthorizedException>()),
            reason: c.name,
          );
          await expectLater(
            rooms.editMessage(
              beaconId: beaconId,
              messageId: own,
              userId: c.id,
              newBody: 'edited',
            ),
            throwsA(isA<UnauthorizedException>()),
            reason: c.name,
          );
          await expectLater(
            rooms.deleteMessage(
              beaconId: beaconId,
              messageId: own,
              userId: c.id,
            ),
            throwsA(isA<UnauthorizedException>()),
            reason: c.name,
          );
        }
      }
    });

    test('mentions reach exactly the audience; the author hears every '
        'question', () async {
      final lobbyId = await openAsAuthor();
      final everyone = matrix.map((c) => '@${c.id.substring(2, 8)}').join(' ');
      await rooms.createMessage(
        beaconId: beaconId,
        userId: author,
        body: 'Hello $everyone',
        threadItemId: lobbyId,
      );
      expect(intents.mentioned, {
        for (final c in matrix)
          if (c.expected.canRead && c.id != author) c.id,
      });

      intents.clear();
      await rooms.createMessage(
        beaconId: beaconId,
        userId: offerer,
        body: 'Which Saturday?',
        threadItemId: lobbyId,
      );
      expect(intents.directed, {author});
    });

    test('realtime: the audience outside the General room gets the hint, '
        'with no Questions text painted', () async {
      final listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      final notifications = <Map<String, dynamic>>[];
      await listener.execute('LISTEN entity_changes');
      final sub = listener.channels['entity_changes'].listen(
        (payload) =>
            notifications.add(jsonDecode(payload) as Map<String, dynamic>),
      );
      addTearDown(() async {
        await sub.cancel();
        await listener.close();
      });
      final lobbyId = await openAsAuthor();
      final posted = await rooms.createMessage(
        beaconId: beaconId,
        userId: forwardee,
        body: 'Only for Questions',
        threadItemId: lobbyId,
      );
      final messageId = posted['id']! as String;
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      Set<String> recipients() => {
        for (final n in notifications)
          if (n['entity'] == 'room_message' && n['message_id'] == messageId)
            ...(n['user_ids'] as List).cast<String>(),
      };
      final audience = {
        for (final c in matrix)
          if (c.expected.canRead) c.id,
      };
      while (DateTime.now().isBefore(deadline) &&
          !recipients().containsAll(audience)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(recipients(), containsAll(audience));
      // Peer blocked the sender: not even a bare hint.
      expect(recipients(), isNot(contains(peer)));
      for (final c in matrix) {
        if (!c.expected.canRead && c.id != helper) {
          expect(recipients(), isNot(contains(c.id)), reason: c.name);
        }
      }
      expect(
        await RoomMessageSnapshotLookup(db).findEligibleInsert(
          messageId: messageId,
          beaconId: beaconId,
        ),
        isNull,
      );
    });

    test('blocks between recipients hide each other both ways', () async {
      final lobbyId = await openAsAuthor();
      final fromForwardee = await rooms.createMessage(
        beaconId: beaconId,
        userId: forwardee,
        body: 'from forwardee',
        threadItemId: lobbyId,
      );
      await rooms.createMessage(
        beaconId: beaconId,
        userId: peer,
        body: 'from peer',
        threadItemId: lobbyId,
      );
      expect(await bodiesFor(peer, lobbyId), isNot(contains('from forwardee')));
      expect(await bodiesFor(forwardee, lobbyId), isNot(contains('from peer')));
      expect(
        await bodiesFor(offerer, lobbyId),
        containsAll(['from forwardee', 'from peer']),
      );
      // No acting on, replying to or mentioning a hidden person.
      await expectLater(
        rooms.reactionToggle(
          beaconId: beaconId,
          messageId: fromForwardee['id']! as String,
          userId: peer,
          emoji: '👍',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      await expectLater(
        rooms.createMessage(
          beaconId: beaconId,
          userId: peer,
          body: 'reply',
          threadItemId: lobbyId,
          replyToMessageId: fromForwardee['id']! as String,
        ),
        throwsA(isA<IdWrongException>()),
      );
      intents.clear();
      await rooms.createMessage(
        beaconId: beaconId,
        userId: peer,
        body: '@forwar are you coming?',
        threadItemId: lobbyId,
      );
      expect(intents.mentioned, isNot(contains(forwardee)));
      // A third person's reply to the hidden message does not reveal its id.
      await rooms.createMessage(
        beaconId: beaconId,
        userId: offerer,
        body: 'replying to forwardee',
        threadItemId: lobbyId,
        replyToMessageId: fromForwardee['id']! as String,
      );
      final peerView = await rooms.listMessages(
        beaconId: beaconId,
        userId: peer,
        threadItemId: lobbyId,
      );
      final reply = peerView.singleWhere(
        (m) => m['body'] == 'replying to forwardee',
      );
      expect(reply['replyToMessageId'], isNull);
      expect(reply['replyToBodyExcerpt'], isNull);
      // The deep link to a hidden message resolves to nothing.
      await expectLater(
        rooms.roomMessageTarget(
          beaconId: beaconId,
          messageId: fromForwardee['id']! as String,
          userId: peer,
        ),
        throwsA(isA<IdNotFoundException>()),
      );
    });

    test('withdrawing turns a recipient read-only; offering again restores '
        'writing; cancelling the forward removes access', () async {
      final lobbyId = await openAsAuthor();
      await offer(forwardee);
      await offer(forwardee, status: 1);
      expect(
        (await lobby.accessLevels(
          beaconId: beaconId,
          userIds: [forwardee],
        ))[forwardee],
        QuestionsAccess.read,
      );
      await offer(forwardee);
      expect(
        (await lobby.accessLevels(
          beaconId: beaconId,
          userIds: [forwardee],
        ))[forwardee],
        QuestionsAccess.write,
      );
      await offer(forwardee, status: 1);
      await sql(
        'UPDATE public.beacon_forward_edge SET cancelled_at = now() '
        "WHERE recipient_id = '$forwardee'",
      );
      await expectLater(
        bodiesFor(forwardee, lobbyId),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('a ban outlives withdrawing and offering again; the author lifts '
        'it; earlier messages stay', () async {
      final lobbyId = await openAsAuthor();
      await rooms.createMessage(
        beaconId: beaconId,
        userId: forwardee,
        body: 'I can bring a ladder',
        threadItemId: lobbyId,
      );
      await rooms.banFromLobby(
        beaconId: beaconId,
        userId: author,
        bannedUserId: forwardee,
      );
      await offer(forwardee);
      await expectLater(
        rooms.beaconLobby(beaconId: beaconId, userId: forwardee),
        throwsA(isA<BeaconLobbyAccessException>()),
      );
      expect(
        await bodiesFor(offerer, lobbyId),
        contains('I can bring a ladder'),
      );
      final forAuthor = await rooms.beaconLobby(
        beaconId: beaconId,
        userId: author,
      );
      expect(forAuthor['bannedUserIds'], containsAll([banned, forwardee]));
      expect(
        (forAuthor['banned']! as List).cast<Map<String, Object?>>().map(
          (b) => b['title'],
        ),
        contains('forwar'),
      );
      await rooms.unbanFromLobby(
        beaconId: beaconId,
        userId: author,
        bannedUserId: forwardee,
      );
      expect(await bodiesFor(forwardee, lobbyId), isNotEmpty);
    });

    test('only the author bans, never themselves, never an unknown user', () async {
      await expectLater(
        rooms.banFromLobby(
          beaconId: beaconId,
          userId: steward,
          bannedUserId: offerer,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      await expectLater(
        rooms.banFromLobby(
          beaconId: beaconId,
          userId: author,
          bannedUserId: author,
        ),
        throwsA(isA<IdWrongException>()),
      );
      await expectLater(
        rooms.banFromLobby(
          beaconId: beaconId,
          userId: author,
          bannedUserId: 'Unobody00001',
        ),
        throwsA(isA<IdNotFoundException>()),
      );
    });

    test('a closed Request: everyone who could read still reads, nobody '
        'writes', () async {
      final lobbyId = await openAsAuthor();
      await sql("UPDATE public.beacon SET status = 6 WHERE id = '$beaconId'");
      final closedRooms = buildRooms(
        hierarchy: FakeBeaconHierarchyRepository()
          ..statusOverride = BeaconStatus.closed,
      );
      final levels = await lobby.accessLevels(
        beaconId: beaconId,
        userIds: [for (final c in matrix) c.id],
      );
      for (final c in matrix) {
        expect(
          levels[c.id],
          c.expected.canRead ? QuestionsAccess.read : QuestionsAccess.none,
          reason: c.name,
        );
      }
      final opened = await closedRooms.beaconLobby(
        beaconId: beaconId,
        userId: forwardee,
      );
      expect(opened['canPost'], isFalse);
      expect(await bodiesFor(forwardee, lobbyId), isEmpty);
      await expectLater(
        closedRooms.createMessage(
          beaconId: beaconId,
          userId: author,
          body: 'too late',
          threadItemId: lobbyId,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Questions stay out of General and its features', () async {
      final lobbyId = await openAsAuthor();
      Future<Object?> lastActivity() async => (await writer.execute(
        "SELECT last_activity_at FROM public.beacon WHERE id = '$beaconId'",
      )).single.single;
      final activityBefore = await lastActivity();
      final posted = await rooms.createMessage(
        beaconId: beaconId,
        userId: forwardee,
        body: 'Which Saturday?',
        threadItemId: lobbyId,
      );
      final messageId = posted['id']! as String;
      final general = await rooms.listMessages(
        beaconId: beaconId,
        userId: author,
      );
      expect([for (final m in general) m['body']], isNot(contains('Which Saturday?')));
      // General-only features cannot point at a Questions message.
      await expectLater(
        sql(
          'INSERT INTO public.coordination_item (id, beacon_id, kind, status, '
          "creator_id, published, linked_message_id) VALUES ('Cqlink1', "
          "'$beaconId', 2, 0, '$author', true, '$messageId')",
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        rooms.roomMessageMarkSemanticDone(
          beaconId: beaconId,
          userId: author,
          messageId: messageId,
        ),
        throwsA(isA<DiscussionScopeDisabledException>()),
      );
      // No attachments: room images are not gated by the Questions policy.
      await expectLater(
        rooms.createMessage(
          beaconId: beaconId,
          userId: author,
          body: 'a photo',
          threadItemId: lobbyId,
          attachmentBytes: Stream.value(Uint8List.fromList([1, 2, 3])),
          attachmentFilename: 'a.png',
        ),
        throwsA(isA<IdWrongException>()),
      );
      // Facts are General-audience: never quoted into Questions.
      await expectLater(
        rooms.createMessage(
          beaconId: beaconId,
          userId: author,
          body: 'see the fact',
          threadItemId: lobbyId,
          quotedFactCardId: 'Fnone',
          quotedFactRevisionSeq: 1,
        ),
        throwsA(isA<IdWrongException>()),
      );
      // The Request's activity timestamp (readable by discovery readers)
      // does not move for Questions.
      expect(await lastActivity(), activityBefore);
      // Not listed as a coordination item.
      final listed = await CoordinationItemRepository(db).listByBeacon(
        beaconId,
        viewerUserId: author,
      );
      expect(
        listed.map((i) => i.item.kind),
        isNot(contains(coordinationItemKindLobby)),
      );
    });

    test('other item threads stay disabled (DB guard)', () async {
      await sql(
        'INSERT INTO public.coordination_item (id, beacon_id, kind, status, '
        "creator_id, published) VALUES ('Cask1', '$beaconId', 2, 0, "
        "'$author', true)",
      );
      await expectLater(
        sql(
          'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, '
          "body, thread_item_id) VALUES ('Mthread1', '$beaconId', "
          "'$author', 'x', 'Cask1')",
        ),
        throwsA(isA<ServerException>()),
      );
    });
  }, skip: skipReason ?? false);
}
