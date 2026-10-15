@Tags(['pg'])
library;

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
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_lobby_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
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

  @override
  Future<AttentionDispatchIntent> roomMentioned({
    required String beaconId,
    required String messageId,
    required String actorUserId,
    required Set<String> recipientUserIds,
    required String excerpt,
    required String sourceEventKey,
    String? threadItemId,
  }) async {
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
  }) async {
    directed.addAll(recipientUserIds);
    return _intent;
  }
}

final class _NoopDispatch implements AttentionDispatchPort {
  @override
  Future<void> record(AttentionDispatchIntent intent) async {}
}

/// U088 — a "lobby" per Request: a discussion for the people who offered
/// help (and the author), before or without admission to the main
/// discussion. It reuses the dormant item-thread scope (`thread_item_id` on
/// `beacon_room_message`) with one `coordination_item` of kind 7 per Request.
/// The author can ban a person from the lobby; a banned person can neither
/// read nor post there until the author lets them back in.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_LOBBY_TEST_DB',
    defaultNamePrefix: 'tentura_test_beacon_lobby',
  );
  final skipReason = await pgSkipReason(target);

  const authorId = 'Ulobbyauth01';
  const ninaId = 'Ulobbynina01';
  const omarId = 'Ulobbyomar01';
  const strangerId = 'Ulobbystra01';
  const beaconId = 'Blobbyreq001';

  group('Request lobby (U088)', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late BeaconRoomRepository room;
    late BeaconLobbyRepository lobby;
    late BeaconRoomCase rooms;

    Future<void> offer(String userId, {int status = 0}) => writer.execute(
      Sql.named(
        'INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, '
        'status) VALUES (@b, @u, @m, @s) ON CONFLICT (beacon_id, user_id) '
        'DO UPDATE SET status = EXCLUDED.status',
      ),
      parameters: {
        'b': beaconId,
        'u': userId,
        'm': 'I have a van',
        's': status,
      },
    );

    Future<List<String>> lobbyBodies(String viewer, String lobbyId) async {
      final rows = await rooms.listMessages(
        beaconId: beaconId,
        userId: viewer,
        threadItemId: lobbyId,
      );
      return [for (final r in rows) r['body']! as String];
    }

    BeaconRoomCase buildRooms({
      AttentionIntentCase? intents,
      FakeBeaconHierarchyRepository? hierarchy,
    }) => BeaconRoomCase(
      room,
      CoordinationItemRepository(db),
      _FakeFactCards(),
      _FakeImages(),
      _FakeTasks(),
      _FakeRemoteStorage(),
      _FakePolling(),
      _FakeUploadQuota(),
      FakeUserBlockRepository(),
      PassThroughMutatingUnitOfWork(),
      hierarchy ?? FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
      attentionIntents: intents,
      attention: intents == null
          ? null
          : TransactionalAttentionCase(
              PassThroughMutatingUnitOfWork(),
              _NoopDispatch(),
            ),
      lobby: lobby,
      env: Env(environment: Environment.test),
      logger: Logger('beacon_lobby_pg_test'),
    );

    setUpAll(() async {
      if (skipReason != null) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = TenturaDb(target.databaseEnv);
      room = BeaconRoomRepository(db);
      lobby = BeaconLobbyRepository(db);
      rooms = buildRooms();
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      if (skipReason != null) return;
      await writer.execute(
        'TRUNCATE TABLE public.beacon_room_message, public.beacon_room_seen, '
        'public.coordination_item, public.beacon_help_offer, public.beacon, '
        'public."user" CASCADE',
      );
      await writer.execute(
        'INSERT INTO public."user" (id, display_name, public_key) VALUES '
        "('$authorId', 'Anna', 'k1'), ('$ninaId', 'Nina', 'k2'), "
        "('$omarId', 'Omar', 'k3'), ('$strangerId', 'Stranger', 'k4')",
      );
      await writer.execute(
        'INSERT INTO public.beacon (id, user_id, title, description, '
        'status, kind, is_discoverable, published_at, created_at, '
        "updated_at) VALUES ('$beaconId', '$authorId', 'Moving day', 'desc', "
        "0, 0, true, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z')",
      );
    });

    test('one lobby per Request, created on first open', () async {
      final a = await rooms.beaconLobby(beaconId: beaconId, userId: authorId);
      final b = await rooms.beaconLobby(beaconId: beaconId, userId: authorId);
      expect(a['lobbyId'], isNotEmpty);
      expect(b['lobbyId'], a['lobbyId']);
      final kinds = await writer.execute(
        "SELECT kind FROM public.coordination_item WHERE beacon_id = '$beaconId'",
      );
      expect([for (final r in kinds) r[0]], [coordinationItemKindLobby]);
    });

    test(
      'the author and people who offered help can open it; others not',
      () async {
        await offer(ninaId);
        await offer(omarId, status: 1); // withdrawn
        expect(
          (await rooms.beaconLobby(
            beaconId: beaconId,
            userId: ninaId,
          ))['canPost'],
          isTrue,
        );
        await expectLater(
          rooms.beaconLobby(beaconId: beaconId, userId: strangerId),
          throwsA(isA<UnauthorizedException>()),
        );
        await expectLater(
          rooms.beaconLobby(beaconId: beaconId, userId: omarId),
          throwsA(isA<UnauthorizedException>()),
        );
      },
    );

    test(
      'lobby messages stay in the lobby, out of the main discussion',
      () async {
        await offer(ninaId);
        final lobbyId =
            (await rooms.beaconLobby(
                  beaconId: beaconId,
                  userId: ninaId,
                ))['lobbyId']!
                as String;
        await rooms.createMessage(
          beaconId: beaconId,
          userId: ninaId,
          body: 'Which Saturday?',
          threadItemId: lobbyId,
        );
        await rooms.createMessage(
          beaconId: beaconId,
          userId: authorId,
          body: 'The 18th',
          threadItemId: lobbyId,
        );
        expect(
          await lobbyBodies(authorId, lobbyId),
          unorderedEquals([
            'Which Saturday?',
            'The 18th',
          ]),
        );
        expect(await lobbyBodies(ninaId, lobbyId), hasLength(2));
        final main = await rooms.listMessages(
          beaconId: beaconId,
          userId: authorId,
        );
        expect([
          for (final m in main) m['body'],
        ], isNot(contains('Which Saturday?')));
        await expectLater(
          rooms.listMessages(
            beaconId: beaconId,
            userId: strangerId,
            threadItemId: lobbyId,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      },
    );

    test(
      'the author bans a person: no reading, no posting, until let back in',
      () async {
        await offer(ninaId);
        final lobbyId =
            (await rooms.beaconLobby(
                  beaconId: beaconId,
                  userId: authorId,
                ))['lobbyId']!
                as String;

        await rooms.banFromLobby(
          beaconId: beaconId,
          userId: authorId,
          bannedUserId: ninaId,
        );
        await expectLater(
          rooms.listMessages(
            beaconId: beaconId,
            userId: ninaId,
            threadItemId: lobbyId,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
        await expectLater(
          rooms.createMessage(
            beaconId: beaconId,
            userId: ninaId,
            body: 'hello?',
            threadItemId: lobbyId,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
        final forAuthor = await rooms.beaconLobby(
          beaconId: beaconId,
          userId: authorId,
        );
        expect(forAuthor['bannedUserIds'], [ninaId]);

        // Withdrawing and offering again does not lift the ban.
        await offer(ninaId, status: 1);
        await offer(ninaId);
        await expectLater(
          rooms.beaconLobby(beaconId: beaconId, userId: ninaId),
          throwsA(isA<UnauthorizedException>()),
        );

        await rooms.unbanFromLobby(
          beaconId: beaconId,
          userId: authorId,
          bannedUserId: ninaId,
        );
        expect(await lobbyBodies(ninaId, lobbyId), isEmpty);
      },
    );

    test('only the author bans, and not themselves', () async {
      await offer(ninaId);
      await offer(omarId);
      await expectLater(
        rooms.banFromLobby(
          beaconId: beaconId,
          userId: ninaId,
          bannedUserId: omarId,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      await expectLater(
        rooms.banFromLobby(
          beaconId: beaconId,
          userId: authorId,
          bannedUserId: authorId,
        ),
        throwsA(isA<IdWrongException>()),
      );
    });

    test(
      'lobby text reaches only lobby members: no @mention or reply notice '
      'for a main-discussion member without lobby access',
      () async {
        // Nina and Omar are both admitted to the main discussion; only Nina
        // offered help, so only Nina is in the lobby.
        await writer.execute(
          "UPDATE public.\"user\" SET handle = 'nina' WHERE id = '$ninaId'",
        );
        await writer.execute(
          "UPDATE public.\"user\" SET handle = 'omar' WHERE id = '$omarId'",
        );
        await writer.execute(
          'INSERT INTO public.beacon_participant (id, beacon_id, user_id, '
          "role, status, room_access) VALUES ('Plobbypart01', '$beaconId', "
          "'$ninaId', 0, 0, 3), ('Plobbypart02', '$beaconId', '$omarId', 0, "
          '0, 3)',
        );
        await offer(ninaId);
        final intents = _RecordingIntents();
        final notifying = buildRooms(intents: intents);
        final lobbyId =
            (await notifying.beaconLobby(
                  beaconId: beaconId,
                  userId: authorId,
                ))['lobbyId']!
                as String;

        await notifying.createMessage(
          beaconId: beaconId,
          userId: authorId,
          body: '@omar @nina which Saturday?',
          threadItemId: lobbyId,
        );
        expect(intents.mentioned, {ninaId});

        // Nina withdraws her offer, so she leaves the lobby; a reply to her
        // old lobby message must not carry the lobby text to her.
        final ninaMessage = await notifying.createMessage(
          beaconId: beaconId,
          userId: ninaId,
          body: 'The 18th works',
          threadItemId: lobbyId,
        );
        await offer(ninaId, status: 1);
        await notifying.createMessage(
          beaconId: beaconId,
          userId: authorId,
          body: 'Great, see you then',
          threadItemId: lobbyId,
          replyToMessageId: ninaMessage['id']! as String,
        );
        expect(intents.directed, isEmpty);
      },
    );

    test(
      'a closed Request: the lobby opens read-only (canPost false)',
      () async {
        await offer(ninaId);
        final open = await rooms.beaconLobby(
          beaconId: beaconId,
          userId: ninaId,
        );
        expect(open['canPost'], isTrue);

        final closedRooms = buildRooms(
          hierarchy: FakeBeaconHierarchyRepository()
            ..statusOverride = BeaconStatus.closed,
        );
        final closed = await closedRooms.beaconLobby(
          beaconId: beaconId,
          userId: ninaId,
        );
        expect(closed['canPost'], isFalse);
      },
    );

    test('other item threads stay disabled (DB guard)', () async {
      await writer.execute(
        'INSERT INTO public.coordination_item (id, beacon_id, kind, status, '
        "creator_id, published) VALUES ('Cask1', '$beaconId', 2, 0, "
        "'$authorId', true)",
      );
      await expectLater(
        writer.execute(
          'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, '
          "body, thread_item_id) VALUES ('Mthread1', '$beaconId', "
          "'$authorId', 'x', 'Cask1')",
        ),
        throwsA(isA<ServerException>()),
      );
    });
  }, skip: skipReason ?? false);
}
