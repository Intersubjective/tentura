@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_lobby_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';

/// #759: the "New fact" form (Pinned facts → Add fact) posted its message but
/// the pin that follows it was refused ("Posted to the discussion, but the
/// fact could not be pinned."), while "Pin as fact" on an older message
/// worked.
///
/// These tests replay the form's two requests exactly as the client sends
/// them (`BeaconViewCase.pinFactFromComposer`):
///
/// 1. `RoomMessageCreate(beaconId, body)` with no thread (General), no reply,
///    no quote, no client message id and empty mention lists;
/// 2. `BeaconFactCardPin(beaconId, factText: body.trim(), visibility,
///    sourceMessageId: id from 1)` the moment 1 answers, by the same user;
///    visibility 0 = "Public — visible beyond the discussion", 1 =
///    "Discussion only" (client and server `BeaconFactCardVisibilityBits`
///    agree).
///
/// Both go through the production use cases on the production unit of work
/// (`MutatingUnitOfWork`), as the Request's author, on an open Request
/// ("Looking for helpers": status 0, published) that already has one pinned
/// fact. Every pin must succeed and the fact must be listed; a refusal fails
/// with the server's own exception so the rule that refused it is named.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_COMPOSER_PIN_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_composer_pin',
  );
  final skipReason = await pgSkipReason(target);

  group('#759 New fact: post then pin (client composer flow)', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late BeaconRoomCase rooms;
    late BeaconFactCardCase facts;

    BeaconRoomCase buildRooms(TenturaDb database) => BeaconRoomCase(
      BeaconRoomRepository(database),
      CoordinationItemRepository(database),
      BeaconFactCardRepository(database, BeaconRoomRepository(database)),
      _UnusedImages(),
      _UnusedTasks(),
      _UnusedRemoteStorage(),
      _UnusedPolling(),
      _UnusedUploadQuota(),
      FakeUserBlockRepository(),
      MutatingUnitOfWork(database),
      FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
      beaconRepository: BeaconRepository(database),
      lobby: BeaconLobbyRepository(database),
      env: Env(environment: Environment.test),
      logger: Logger('beacon_fact_composer_pin_pg_test.rooms'),
    );

    BeaconFactCardCase buildFacts(TenturaDb database) {
      final room = BeaconRoomRepository(database);
      return BeaconFactCardCase(
        BeaconFactCardRepository(database, room),
        room,
        _UnusedImages(),
        _UnusedTasks(),
        BeaconHierarchyRepository(database),
        BeaconAccessRepository(database),
        beaconRepository: BeaconRepository(database),
        env: Env(environment: Environment.test),
        logger: Logger('beacon_fact_composer_pin_pg_test.facts'),
      );
    }

    /// Step 2 of the form; a refusal fails the test with the server's words.
    Future<void> pinOrFail(
      BeaconFactCardCase useCase, {
      required String factText,
      required int visibility,
      required String sourceMessageId,
    }) async {
      try {
        await useCase.pin(
          beaconId: _beaconId,
          factText: factText,
          visibility: visibility,
          userId: _authorId,
          sourceMessageId: sourceMessageId,
        );
      } on Object catch (e) {
        fail(
          'the pin after RoomMessageCreate was refused (#759): '
          '${e.runtimeType}: $e',
        );
      }
    }

    /// Step 1 of the form, as `BeaconThreadsCase.createMessage` sends it.
    Future<String> post(
      BeaconRoomCase useCase,
      String body, {
      String? threadItemId,
    }) async {
      final posted = await useCase.createMessage(
        beaconId: _beaconId,
        userId: _authorId,
        body: body,
        threadItemId: threadItemId,
      );
      expect(posted['beaconId'], _beaconId);
      return posted['id']! as String;
    }

    /// The whole form: post, then pin the posted message at once.
    Future<String> composerPin({
      required String body,
      required int visibility,
      BeaconRoomCase? roomCase,
      BeaconFactCardCase? factCase,
    }) async {
      final messageId = await post(roomCase ?? rooms, body);
      await pinOrFail(
        factCase ?? facts,
        factText: body.trim(),
        visibility: visibility,
        sourceMessageId: messageId,
      );
      return messageId;
    }

    Future<List<Map<String, Object?>>> listed() =>
        facts.list(beaconId: _beaconId, userId: _authorId);

    void expectListed(
      List<Map<String, Object?>> rows, {
      required String sourceMessageId,
      required String factText,
      required int visibility,
    }) {
      final matching = [
        for (final r in rows)
          if (r['sourceMessageId'] == sourceMessageId) r,
      ];
      expect(
        matching,
        hasLength(1),
        reason: 'the posted message must carry exactly one listed fact',
      );
      expect(matching.single['factText'], factText);
      expect(matching.single['visibility'], visibility);
      expect(matching.single['status'], BeaconFactCardStatusBits.active);
    }

    setUpAll(() async {
      if (skipReason != null) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = TenturaDb(target.databaseEnv);
      rooms = buildRooms(db);
      facts = buildFacts(db);
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<void> seedExistingFact({required int visibility}) async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@id, @beacon, @author, @body)
'''),
        parameters: {
          'id': _olderMessageId,
          'beacon': _beaconId,
          'author': _authorId,
          'body': _olderFactText,
        },
      );
      // The fact the room already has, pinned from the message menu.
      await pinOrFail(
        facts,
        factText: _olderFactText,
        visibility: visibility,
        sourceMessageId: _olderMessageId,
      );
    }

    setUp(() async {
      if (skipReason != null) return;
      await writer.execute(
        'TRUNCATE TABLE public.beacon_room_message, '
        'public.coordination_item, public.beacon, public."user" CASCADE',
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, 'QA Alice', @key)
'''),
        parameters: {
          'id': _authorId,
          'key': pgTestPublicKey('factcomposer759', 1),
        },
      );
      // "Looking for helpers": an open (status 0), published Request with no
      // offers yet.
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES (@beacon, @author, 'QA684 R1', 'd', 0, now(), false)
'''),
        parameters: {'beacon': _beaconId, 'author': _authorId},
      );
    });

    for (final existing in [
      BeaconFactCardVisibilityBits.public,
      BeaconFactCardVisibilityBits.room,
    ]) {
      final existingName = existing == BeaconFactCardVisibilityBits.public
          ? 'public'
          : 'discussion-only';
      for (final (name, visibility) in [
        ('Discussion only', BeaconFactCardVisibilityBits.room),
        ('Public', BeaconFactCardVisibilityBits.public),
      ]) {
        test(
          '$name: the posted message is pinned and listed beside an '
          'existing $existingName fact',
          () async {
            await seedExistingFact(visibility: existing);
            final messageId = await composerPin(
              body: 'QA609 factB',
              visibility: visibility,
            );
            final rows = await listed();
            expect(rows, hasLength(2), reason: 'the older fact and the new');
            expectListed(
              rows,
              sourceMessageId: messageId,
              factText: 'QA609 factB',
              visibility: visibility,
            );
            expectListed(
              rows,
              sourceMessageId: _olderMessageId,
              factText: _olderFactText,
              visibility: existing,
            );
          },
        );
      }
    }

    test('a second new fact while one new fact already exists', () async {
      await seedExistingFact(visibility: BeaconFactCardVisibilityBits.public);
      final first = await composerPin(
        body: 'QA609 factB',
        visibility: BeaconFactCardVisibilityBits.room,
      );
      final second = await composerPin(
        body: 'QA609 factC',
        visibility: BeaconFactCardVisibilityBits.room,
      );
      final rows = await listed();
      expect(rows, hasLength(3));
      expectListed(
        rows,
        sourceMessageId: first,
        factText: 'QA609 factB',
        visibility: BeaconFactCardVisibilityBits.room,
      );
      expectListed(
        rows,
        sourceMessageId: second,
        factText: 'QA609 factC',
        visibility: BeaconFactCardVisibilityBits.room,
      );
    });

    test('a new fact whose text equals an existing fact', () async {
      await seedExistingFact(visibility: BeaconFactCardVisibilityBits.room);
      final messageId = await composerPin(
        body: _olderFactText,
        visibility: BeaconFactCardVisibilityBits.room,
      );
      final rows = await listed();
      expect(rows, hasLength(2), reason: 'same text, different message');
      expectListed(
        rows,
        sourceMessageId: messageId,
        factText: _olderFactText,
        visibility: BeaconFactCardVisibilityBits.room,
      );
    });

    test('a body with surrounding whitespace pins its trimmed text', () async {
      await seedExistingFact(visibility: BeaconFactCardVisibilityBits.public);
      // The form sends the raw text as the message and the trimmed text as
      // the fact (`pinFactTextForPin`).
      final messageId = await post(rooms, '  QA609 fact 10:41 \n');
      await pinOrFail(
        facts,
        factText: 'QA609 fact 10:41',
        visibility: BeaconFactCardVisibilityBits.room,
        sourceMessageId: messageId,
      );
      expectListed(
        await listed(),
        sourceMessageId: messageId,
        factText: 'QA609 fact 10:41',
        visibility: BeaconFactCardVisibilityBits.room,
      );
    });

    test(
      'post and pin on two separate database handles (two server '
      'connections), the pin issued the moment the post answers',
      () async {
        await seedExistingFact(visibility: BeaconFactCardVisibilityBits.public);
        final otherDb = TenturaDb(target.databaseEnv);
        try {
          final messageId = await composerPin(
            body: 'QA609 factD',
            visibility: BeaconFactCardVisibilityBits.room,
            roomCase: buildRooms(db),
            factCase: buildFacts(otherDb),
          );
          expectListed(
            await listed(),
            sourceMessageId: messageId,
            factText: 'QA609 factD',
            visibility: BeaconFactCardVisibilityBits.room,
          );
        } finally {
          await otherDb.close();
        }
      },
    );

    test(
      'contrast: a message in the Questions sub-thread is refused by the '
      'General-only guard and writes no fact (the form never posts there)',
      () async {
        await seedExistingFact(visibility: BeaconFactCardVisibilityBits.public);
        final lobbyId =
            (await rooms.beaconLobby(
                  beaconId: _beaconId,
                  userId: _authorId,
                ))['lobbyId']!
                as String;
        final messageId = await post(
          rooms,
          'QA609 question',
          threadItemId: lobbyId,
        );
        await expectLater(
          facts.pin(
            beaconId: _beaconId,
            factText: 'QA609 question',
            visibility: BeaconFactCardVisibilityBits.room,
            userId: _authorId,
            sourceMessageId: messageId,
          ),
          throwsA(isA<Object>()),
        );
        final rows = await listed();
        expect(rows, hasLength(1), reason: 'only the older fact');
        expect(
          rows.where((r) => r['sourceMessageId'] == messageId),
          isEmpty,
        );
      },
    );
  }, skip: skipReason ?? false);
}

const _authorId = 'Uf759author1';
const _beaconId = 'Bf759beacon1';
const _olderMessageId = 'Rf759older01';
const _olderFactText = 'QA609 factA';

class _UnusedImages extends Fake implements ImageRepositoryPort {}

class _UnusedTasks extends Fake implements TaskRepositoryPort {}

class _UnusedRemoteStorage extends Fake implements RemoteStoragePort {}

class _UnusedPolling extends Fake implements PollingRepositoryPort {}

class _UnusedUploadQuota extends Fake implements UploadQuotaRepositoryPort {}
