@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/polling_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Uroomgateauth1';
const _forwarder = 'Uroomgatefwd01';
const _recipient = 'Uroomgaterec01';
const _users = [_author, _forwarder, _recipient];

const _post = 'Broomgatepost01';
const _request = 'Broomgatereq001';
const _postRootMessage = 'Rroomgatepost01';
const _requestRootMessage = 'Rroomgatereq001';
const _recipientPostMessage = 'Rroomgaterecmsg1';
const _roomEvent = 'Vroomgateevent01';
const _postAttachment = 'Aroomgatepost001';
const _requestAttachment = 'Aroomgatereq0001';

/// A Post member may have been admitted through somebody else's forward, so a
/// block between the author and that member does not remove their room
/// participant row. The room gate must therefore deny a blocked Post member
/// on every room entry point, while the same blocks leave a Request room
/// exactly as it is.
///
/// Real repositories over a disposable Postgres; blocks are written through
/// the real block repository without the edge cleanup, because the member
/// reached the Post through the forwarder.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_ROOM_BLOCK_GATE_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_room_block',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Room gate with blocks between the author and a member', () {
    late DisposablePgWriterSession session;
    late TenturaDb database;
    late Connection writer;
    late UserBlockRepository blocks;
    late BeaconRoomCase roomCase;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      final env = Env(environment: Environment.test);
      blocks = UserBlockRepository(env, database);
      roomCase = BeaconRoomCase(
        BeaconRoomRepository(database),
        CoordinationItemRepository(database),
        _FakeFactCards(),
        _FakeImages(),
        _FakeTasks(),
        _FakeRemoteStorage(),
        PollingRepository(database),
        _FakeUploadQuota(),
        blocks,
        MutatingUnitOfWork(database),
        FakeBeaconHierarchyRepository(),
        const ProductionDiscussionProductPolicy(),
        beaconRepository: BeaconRepository(database),
        env: env,
        logger: Logger('post_room_block_gate_pg_test'),
      );
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.user_block_intent,
  public.user_block,
  public.beacon_room_message_reaction,
  public.beacon_room_message_attachment,
  public.beacon_activity_event,
  public.beacon_room_message,
  public.beacon_participant,
  public.beacon_forward_edge,
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
          parameters: {
            'id': _users[i],
            'key': pgTestPublicKey('roomgate', i + 1),
          },
        );
      }
      // The Post: the author forwards it to the forwarder, who forwards it on
      // to the recipient. Both recipients are admitted as addressees by the
      // forward-edge trigger.
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
      await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Froomgateedge01', '$_post', '$_author', '$_forwarder'),
  ('Froomgateedge02', '$_post', '$_forwarder', '$_recipient')
''');
      // The Request: the same people, admitted to its room.
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
      await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Froomgateedge03', '$_request', '$_author', '$_forwarder'),
  ('Froomgateedge04', '$_request', '$_forwarder', '$_recipient')
''');
      await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES
  ('Proomgatereqf01', '$_request', '$_forwarder', 0, 0, 3),
  ('Proomgatereqr01', '$_request', '$_recipient', 0, 0, 3)
''');
      await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES
  ('$_postRootMessage', '$_post', '$_author', 'Heads up'),
  ('$_requestRootMessage', '$_request', '$_author', 'Welcome'),
  ('$_recipientPostMessage', '$_post', '$_recipient', 'On my way')
''');
      await writer.execute('''
INSERT INTO public.beacon_activity_event (id, beacon_id, visibility, type, actor_id)
VALUES ('$_roomEvent', '$_post', 1, 0, '$_author')
''');
      await writer.execute('''
INSERT INTO public.beacon_room_message_attachment
  (id, message_id, kind, file_url, mime, file_name)
VALUES
  ('$_postAttachment', '$_postRootMessage', 2, 'room/post.bin',
   'application/octet-stream', 'post.bin'),
  ('$_requestAttachment', '$_requestRootMessage', 2, 'room/request.bin',
   'application/octet-stream', 'request.bin')
''');
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<void> authorBlocksRecipient() =>
        blocks.block(blockerId: _author, blockedId: _recipient, cascadeMode: 0);

    Future<void> recipientBlocksAuthor() =>
        blocks.block(blockerId: _recipient, blockedId: _author, cascadeMode: 0);

    Future<int> reactionCount(String messageId, String userId) async {
      final rows = await writer.execute(
        Sql.named('''
SELECT count(*)::int FROM public.beacon_room_message_reaction
WHERE message_id = @messageId AND user_id = @userId
'''),
        parameters: {'messageId': messageId, 'userId': userId},
      );
      return rows.single.single! as int;
    }

    final directions = <String, Future<void> Function()>{
      'the author blocks the member': authorBlocksRecipient,
      'the member blocks the author': recipientBlocksAuthor,
    };

    for (final MapEntry(key: direction, value: block) in directions.entries) {
      group('Post room when $direction', () {
        setUp(block);

        test('the member cannot list messages', () async {
          await expectLater(
            roomCase.listMessages(beaconId: _post, userId: _recipient),
            throwsA(isA<UnauthorizedException>()),
          );
        });

        test('the member cannot create a message', () async {
          await expectLater(
            roomCase.createMessage(
              beaconId: _post,
              userId: _recipient,
              body: 'Still here?',
            ),
            throwsA(isA<UnauthorizedException>()),
          );
          final rows = await writer.execute('''
SELECT count(*) FROM public.beacon_room_message
WHERE beacon_id = '$_post' AND author_id = '$_recipient'
  AND id <> '$_recipientPostMessage'
''');
          expect(rows.single.single, 0);
        });

        test('the member cannot toggle a reaction', () async {
          await expectLater(
            roomCase.reactionToggle(
              beaconId: _post,
              messageId: _postRootMessage,
              userId: _recipient,
              emoji: '👍',
            ),
            throwsA(isA<UnauthorizedException>()),
          );
          expect(await reactionCount(_postRootMessage, _recipient), 0);
        });

        test('the member cannot list participants', () async {
          await expectLater(
            roomCase.listParticipants(beaconId: _post, userId: _recipient),
            throwsA(isA<UnauthorizedException>()),
          );
        });

        test('the member cannot mark the room seen', () async {
          await expectLater(
            roomCase.markBeaconRoomSeen(beaconId: _post, userId: _recipient),
            throwsA(isA<UnauthorizedException>()),
          );
        });

        test('the member cannot create a poll', () async {
          await expectLater(
            roomCase.createPoll(
              beaconId: _post,
              userId: _recipient,
              question: 'Who is in?',
              variants: const ['Me', 'Not me'],
            ),
            throwsA(isA<UnauthorizedException>()),
          );
          final rows = await writer.execute('''
SELECT count(*) FROM public.beacon_room_message
WHERE beacon_id = '$_post' AND linked_polling_id IS NOT NULL
''');
          expect(rows.single.single, 0);
        });

        test('the member cannot download an attachment', () async {
          await expectLater(
            roomCase.downloadAttachment(
              userId: _recipient,
              attachmentId: _postAttachment,
            ),
            throwsA(isA<UnauthorizedException>()),
          );
        });

        test(
          'the member cannot add an attachment to their own message',
          () async {
            await expectLater(
              roomCase.addMessageAttachment(
                beaconId: _post,
                userId: _recipient,
                messageId: _recipientPostMessage,
                attachmentBytes: Stream.value(Uint8List.fromList([1, 2, 3])),
                attachmentFilename: 'late.bin',
                attachmentMimeType: 'application/octet-stream',
              ),
              throwsA(isA<UnauthorizedException>()),
            );
            final rows = await writer.execute('''
SELECT count(*) FROM public.beacon_room_message_attachment
WHERE message_id = '$_recipientPostMessage'
''');
            expect(rows.single.single, 0);
          },
        );

        test('the member cannot edit their own message', () async {
          await expectLater(
            roomCase.editMessage(
              beaconId: _post,
              messageId: _recipientPostMessage,
              userId: _recipient,
              newBody: 'Edited after the block',
            ),
            throwsA(isA<UnauthorizedException>()),
          );
          final rows = await writer.execute('''
SELECT body FROM public.beacon_room_message WHERE id = '$_recipientPostMessage'
''');
          expect(rows.single.single, 'On my way');
        });

        test('the member cannot delete their own message', () async {
          await expectLater(
            roomCase.deleteMessage(
              beaconId: _post,
              messageId: _recipientPostMessage,
              userId: _recipient,
            ),
            throwsA(isA<UnauthorizedException>()),
          );
          final rows = await writer.execute('''
SELECT count(*) FROM public.beacon_room_message WHERE id = '$_recipientPostMessage'
''');
          expect(rows.single.single, 1);
        });

        test('the member cannot resolve a message target', () async {
          await expectLater(
            roomCase.roomMessageTarget(
              beaconId: _post,
              messageId: _postRootMessage,
              userId: _recipient,
            ),
            throwsA(isA<UnauthorizedException>()),
          );
        });

        test('the member cannot read the room state', () async {
          await expectLater(
            roomCase.beaconRoomStateGet(beaconId: _post, userId: _recipient),
            throwsA(isA<UnauthorizedException>()),
          );
        });

        test('the member cannot read the room read watermarks', () async {
          await expectLater(
            roomCase.listMainRoomReadWatermarks(
              beaconId: _post,
              userId: _recipient,
            ),
            throwsA(isA<UnauthorizedException>()),
          );
        });

        test('the member cannot list room threads', () async {
          await expectLater(
            roomCase.listThreads(beaconId: _post, userId: _recipient),
            throwsA(isA<UnauthorizedException>()),
          );
        });

        test('the member is not reported as a room member in the inbox '
            'context', () async {
          final rows = await roomCase.inboxRoomContextBatch(
            userId: _recipient,
            beaconIds: const [_post],
          );
          expect(rows.single['isRoomMember'], isFalse);
        });

        test('the member sees only public activity events', () async {
          final events = await roomCase.listActivityEvents(
            beaconId: _post,
            userId: _recipient,
          );
          expect(events.map((e) => e['id']), isNot(contains(_roomEvent)));
        });

        test('the forwarder still reads room state, targets, watermarks, '
            'threads and activity', () async {
          expect(
            await roomCase.beaconRoomStateGet(
              beaconId: _post,
              userId: _forwarder,
            ),
            isNotEmpty,
          );
          expect(
            await roomCase.roomMessageTarget(
              beaconId: _post,
              messageId: _postRootMessage,
              userId: _forwarder,
            ),
            isNotEmpty,
          );
          await roomCase.listMainRoomReadWatermarks(
            beaconId: _post,
            userId: _forwarder,
          );
          expect(
            await roomCase.listThreads(beaconId: _post, userId: _forwarder),
            isNotEmpty,
          );
          final context = await roomCase.inboxRoomContextBatch(
            userId: _forwarder,
            beaconIds: const [_post],
          );
          expect(context.single['isRoomMember'], isTrue);
          final events = await roomCase.listActivityEvents(
            beaconId: _post,
            userId: _forwarder,
          );
          expect(events.map((e) => e['id']), contains(_roomEvent));
        });

        test(
          'the forwarder still edits and deletes their own message',
          () async {
            final created = await roomCase.createMessage(
              beaconId: _post,
              userId: _forwarder,
              body: 'Draft',
            );
            final id = created['id']! as String;
            expect(
              await roomCase.editMessage(
                beaconId: _post,
                messageId: id,
                userId: _forwarder,
                newBody: 'Final',
              ),
              isTrue,
            );
            expect(
              await roomCase.deleteMessage(
                beaconId: _post,
                messageId: id,
                userId: _forwarder,
              ),
              isTrue,
            );
          },
        );

        test('the forwarder still creates a poll', () async {
          final created = await roomCase.createPoll(
            beaconId: _post,
            userId: _forwarder,
            question: 'Who is in?',
            variants: const ['Me', 'Not me'],
          );
          expect(created['id'], isNotNull);
        });

        test('the forwarder still downloads an attachment', () async {
          final file = await roomCase.downloadAttachment(
            userId: _forwarder,
            attachmentId: _postAttachment,
          );
          expect(file.fileName, 'post.bin');
        });

        test('the forwarder still lists messages', () async {
          final messages = await roomCase.listMessages(
            beaconId: _post,
            userId: _forwarder,
          );
          expect(messages.map((m) => m['id']), contains(_postRootMessage));
        });

        test('the forwarder still creates a message', () async {
          final created = await roomCase.createMessage(
            beaconId: _post,
            userId: _forwarder,
            body: 'Welcome aboard',
          );
          expect(created['beaconId'], _post);
        });

        test('the forwarder still toggles a reaction', () async {
          await roomCase.reactionToggle(
            beaconId: _post,
            messageId: _postRootMessage,
            userId: _forwarder,
            emoji: '👍',
          );
          expect(await reactionCount(_postRootMessage, _forwarder), 1);
        });

        test('the author still lists messages', () async {
          final messages = await roomCase.listMessages(
            beaconId: _post,
            userId: _author,
          );
          expect(messages.map((m) => m['id']), contains(_postRootMessage));
        });
      });

      group('Request room when $direction', () {
        setUp(block);

        test('the member still lists messages', () async {
          final messages = await roomCase.listMessages(
            beaconId: _request,
            userId: _recipient,
          );
          expect(messages.map((m) => m['id']), contains(_requestRootMessage));
        });

        test('the member is still refused a new message by the existing '
            'author-block rule', () async {
          await expectLater(
            roomCase.createMessage(
              beaconId: _request,
              userId: _recipient,
              body: 'Still here?',
            ),
            throwsA(isA<UnauthorizedException>()),
          );
        });

        test('the member still toggles a reaction', () async {
          await roomCase.reactionToggle(
            beaconId: _request,
            messageId: _requestRootMessage,
            userId: _recipient,
            emoji: '👍',
          );
          expect(await reactionCount(_requestRootMessage, _recipient), 1);
        });

        test('the member still downloads an attachment', () async {
          final file = await roomCase.downloadAttachment(
            userId: _recipient,
            attachmentId: _requestAttachment,
          );
          expect(file.fileName, 'request.bin');
        });

        test('the forwarder still lists messages and creates one', () async {
          final messages = await roomCase.listMessages(
            beaconId: _request,
            userId: _forwarder,
          );
          expect(messages.map((m) => m['id']), contains(_requestRootMessage));
          final created = await roomCase.createMessage(
            beaconId: _request,
            userId: _forwarder,
            body: 'Welcome aboard',
          );
          expect(created['beaconId'], _request);
        });
      });
    }

    test('without a block the Post member uses the room', () async {
      final messages = await roomCase.listMessages(
        beaconId: _post,
        userId: _recipient,
      );
      expect(messages.map((m) => m['id']), contains(_postRootMessage));
      final created = await roomCase.createMessage(
        beaconId: _post,
        userId: _recipient,
        body: 'Thanks for the heads up',
      );
      expect(created['beaconId'], _post);
    });
  });
}

class _FakeFactCards extends Fake implements BeaconFactCardRepositoryPort {
  @override
  Future<Map<String, String>> publicFactSnippetsByBeaconIds(
    List<String> beaconIds,
  ) async => const {};
}

class _FakeImages extends Fake implements ImageRepositoryPort {}

class _FakeTasks extends Fake implements TaskRepositoryPort {}

class _FakeRemoteStorage extends Fake implements RemoteStoragePort {
  @override
  Future<Uint8List> getObject(String path) async => Uint8List.fromList([1, 2]);

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

class _FakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async => true;
}
