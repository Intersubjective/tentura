@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/polling_act_repository.dart';
import 'package:tentura_server/data/repository/polling_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/polling_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/post_write_guard_fixture.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_ROOM_EXPIRY_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_room_expiry',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late Connection writer;
  late BeaconRoomCase room;
  late PollingCase polls;
  late _Storage storage;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    db = openDisposablePgDatabase(target);
    final env = Env(environment: Environment.test);
    final logger = Logger('PostRoomExpiryGuard');
    final repository = BeaconRoomRepository(db);
    final hierarchy = BeaconHierarchyRepository(db);
    final polling = PollingRepository(db);
    storage = _Storage();
    room = BeaconRoomCase(
      repository,
      CoordinationItemRepository(db),
      _FactCards(),
      _Images(),
      _Tasks(),
      storage,
      polling,
      _Quota(),
      UserBlockRepository(env, db),
      MutatingUnitOfWork(db),
      hierarchy,
      const ProductionDiscussionProductPolicy(),
      beaconRepository: BeaconRepository(db),
      attention: TransactionalAttentionCase(
        MutatingUnitOfWork(db),
        AttentionDispatchRepository(db, logger),
      ),
      env: env,
      logger: logger,
    );
    polls = PollingCase(
      PollingActRepository(db),
      polling,
      repository,
      hierarchy,
      const ProductionDiscussionProductPolicy(),
      env: env,
      logger: logger,
    );
  });
  setUp(() async {
    await seedPostWriteGuard(writer);
    storage
      ..objects.clear()
      ..putCount = 0
      ..onPut = null;
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  Future<void> createMessage() async {
    await room.createMessage(
      beaconId: guardPost,
      userId: guardAuthor,
      body: 'Hello',
    );
  }

  Future<void> editMessage() async {
    await room.editMessage(
      beaconId: guardPost,
      userId: guardAuthor,
      messageId: guardMessage,
      newBody: 'Changed',
    );
  }

  Future<void> react() => room.reactionToggle(
    beaconId: guardPost,
    userId: guardAuthor,
    messageId: guardMessage,
    emoji: '👍',
  );
  Future<void> attach() async {
    await room.addMessageAttachment(
      beaconId: guardPost,
      userId: guardAuthor,
      messageId: guardMessage,
      attachmentBytes: Stream.value(Uint8List.fromList([1, 2, 3])),
      attachmentFilename: 'note.txt',
      attachmentMimeType: 'text/plain',
    );
  }

  Future<void> createPoll() async {
    await room.createPoll(
      beaconId: guardPost,
      userId: guardAuthor,
      question: 'When?',
      variants: ['Today', 'Tomorrow'],
    );
  }

  Future<void> vote() async {
    await polls.create(
      authorId: guardAuthor,
      pollingId: guardPoll,
      variantIds: [guardVariant],
    );
  }

  final operations = <String, (Future<void> Function(), String)>{
    'create a message': (
      createMessage,
      "SELECT count(*)::int FROM public.beacon_room_message WHERE beacon_id = '$guardPost' AND author_id = '$guardAuthor' AND body = 'Hello'",
    ),
    'edit a message': (
      editMessage,
      "SELECT count(*)::int FROM public.beacon_room_message WHERE id = '$guardMessage' AND body = 'Changed'",
    ),
    'toggle a reaction': (
      react,
      "SELECT count(*)::int FROM public.beacon_room_message_reaction WHERE message_id = '$guardMessage' AND user_id = '$guardAuthor' AND emoji = '👍'",
    ),
    'add an attachment': (
      attach,
      "SELECT count(*)::int FROM public.beacon_room_message_attachment WHERE message_id = '$guardMessage' AND file_name = 'note.txt' AND file_url IS NOT NULL",
    ),
    'create a poll': (
      createPoll,
      "SELECT count(*)::int FROM public.beacon_room_message m JOIN public.polling p ON p.id = m.linked_polling_id WHERE m.beacon_id = '$guardPost' AND p.question = 'When?' AND (SELECT count(*) FROM public.polling_variant v WHERE v.polling_id = p.id AND v.description IN ('Today', 'Tomorrow')) = 2",
    ),
    'vote in a poll': (
      vote,
      "SELECT count(*)::int FROM public.polling_act WHERE author_id = '$guardAuthor' AND polling_id = '$guardPoll' AND polling_variant_id = '$guardVariant'",
    ),
  };
  for (final entry in operations.entries) {
    test('an open Post can ${entry.key}', () async {
      await entry.value.$1();
      expect((await writer.execute(entry.value.$2)).single.single, 1);
      if (entry.key == 'add an attachment') {
        expect(storage.putCount, 1);
        expect(storage.objects, hasLength(1));
      }
    });
    test('an expired open Post refuses to ${entry.key} as read-only', () async {
      await archiveGuardPost(writer, 'expired');
      await expectLater(
        entry.value.$1(),
        throwsA(
          isA<BeaconCreateException>().having(
            (e) => e.description,
            'description',
            'Discussion is read-only for this request',
          ),
        ),
      );
    });
  }

  test(
    'an invalid reaction on an open Post keeps its database constraint error',
    () async {
      await expectLater(
        room.reactionToggle(
          beaconId: guardPost,
          userId: guardAuthor,
          messageId: guardMessage,
          emoji: 'x' * 33,
        ),
        throwsA(
          isA<ServerException>()
              .having((e) => e.code, 'SQLSTATE', '23514')
              .having(
                (e) => e.constraintName,
                'constraint',
                'beacon_room_message_reaction_emoji_check',
              ),
        ),
      );
    },
  );

  for (final createWithAttachment in [false, true]) {
    test(
      createWithAttachment
          ? 'a message upload is removed when expiry races message insertion'
          : 'an attachment upload is removed when expiry races attachment insertion',
      () async {
        storage.onPut = () => archiveGuardPost(writer, 'expired');
        Object? failure;
        try {
          if (createWithAttachment) {
            await room.createMessage(
              beaconId: guardPost,
              userId: guardAuthor,
              body: 'With attachment',
              attachmentBytes: Stream.value(Uint8List.fromList([1, 2, 3])),
              attachmentFilename: 'note.txt',
              attachmentMimeType: 'text/plain',
            );
          } else {
            await attach();
          }
        } catch (e) {
          failure = e;
        }
        expect(storage.putCount, 1);
        expect(storage.objects, isEmpty);
        if (createWithAttachment) {
          expect(failure, isNotNull);
        } else {
          expect(
            failure,
            isA<BeaconCreateException>().having(
              (e) => e.description,
              'description',
              'Discussion is read-only for this request',
            ),
          );
        }
        expect(
          (await writer.execute(
            "SELECT count(*)::int FROM public.beacon_room_message_attachment WHERE message_id = '$guardMessage'",
          )).single.single,
          0,
        );
      },
    );
  }

  test(
    'an attachment insertion rejected after expiry reports read-only',
    () async {
      storage.onPut = () => archiveGuardPost(writer, 'expired');
      await expectLater(
        attach(),
        throwsA(
          isA<BeaconCreateException>().having(
            (e) => e.description,
            'description',
            'Discussion is read-only for this request',
          ),
        ),
      );
    },
  );

  for (final state in ['open', 'expired', 'closed']) {
    test('semantic done is refused for a $state Post', () async {
      if (state != 'open') await archiveGuardPost(writer, state);
      await expectLater(
        room.roomMessageMarkSemanticDone(
          beaconId: guardPost,
          userId: guardAuthor,
          messageId: guardMessage,
        ),
        throwsA(isA<BeaconNotRequestException>()),
      );
    });
  }
  test('semantic done works for an open Request', () async {
    await seedPostWriteGuard(writer, kind: 0);
    expect(
      await room.roomMessageMarkSemanticDone(
        beaconId: guardPost,
        userId: guardAuthor,
        messageId: guardMessage,
      ),
      isTrue,
    );
  });
}

final class _FactCards extends Fake implements BeaconFactCardRepositoryPort {}

final class _Images extends Fake implements ImageRepositoryPort {}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task';
}

final class _Quota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async => true;
}

final class _Storage extends Fake implements RemoteStoragePort {
  final objects = <String>{};
  Future<void> Function()? onPut;
  int putCount = 0;
  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    await bytes.drain<void>();
    objects.add(path);
    putCount++;
    await onPut?.call();
    return path;
  }

  @override
  Future<void> removeObject(String path) async {
    objects.remove(path);
  }
}
