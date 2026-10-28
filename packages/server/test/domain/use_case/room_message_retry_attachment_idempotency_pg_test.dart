@Tags(['pg'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/request_change_log_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
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
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_RETRY_ATTACHMENT_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_retry_attachment',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('retried room send with extra attachments', () {
    late Connection writer;
    late TenturaDb database;
    late BeaconRoomCase roomCase;
    late _GatedRemoteStorage storage;

    const authorId = 'Uretryattauth1';
    const beaconId = 'Bretryattbcn01';
    const clientKey = 'send-with-two-extras';

    final vanPhoto = Uint8List.fromList(List.generate(64, (i) => i));
    final routeMap = Uint8List.fromList(List.generate(64, (i) => 200 - i));

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      final roomRepo = BeaconRoomRepository(database);
      final unitOfWork = MutatingUnitOfWork(database);
      final attention = TransactionalAttentionCase(
        unitOfWork,
        AttentionDispatchRepository(
          database,
          Logger('room_message_retry_attachment_pg_test'),
        ),
      );
      final attentionIntents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          roomRepo,
          database,
          HelpOfferRepository(database),
          CommitmentRepository(database),
        ),
        UserRepository(
          Env(environment: Environment.test),
          database,
          _NoopInviteGenealogyRepository(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(database),
        FakeUserBlockRepository(),
      );
      storage = _GatedRemoteStorage();
      roomCase = BeaconRoomCase(
        roomRepo,
        CoordinationItemRepository(database),
        _PgFakeFactCards(),
        _PgFakeImages(),
        _PgFakeTasks(),
        storage,
        _PgFakePolling(),
        _PgFakeUploadQuota(),
        FakeUserBlockRepository(),
        unitOfWork,
        FakeBeaconHierarchyRepository(),
        const ProductionDiscussionProductPolicy(),
        attentionIntents: attentionIntents,
        attention: attention,
        changeLog: RequestChangeLogRepository(database),
        env: Env(environment: Environment.test),
        logger: Logger('room_message_retry_attachment_pg_test'),
      );
    });

    setUp(() async {
      storage.reset();
      await writer.execute('''
TRUNCATE TABLE
  public.beacon_room_message,
  public.attention_channel_delivery,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.notification_outbox,
  public.coordination_item,
  public.beacon_room_state,
  public.beacon,
  public."user"
CASCADE
''');
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@authorId, @authorId, @authorKey)
'''),
        parameters: {
          'authorId': authorId,
          'authorKey': pgTestPublicKey('retryatt', 1),
        },
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@beaconId, @authorId, 'Retry test', 'Body', 0)
'''),
        parameters: {'beaconId': beaconId, 'authorId': authorId},
      );
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    /// One send the way the client makes it: the message first, then each
    /// extra attachment as its own call.
    Future<void> sendWithTwoExtras() async {
      final saved = await roomCase.createMessage(
        beaconId: beaconId,
        userId: authorId,
        body: 'Photos of the van',
        clientMessageId: clientKey,
      );
      for (final (name, bytes) in [
        ('van.txt', vanPhoto),
        ('route.txt', routeMap),
      ]) {
        await roomCase.addMessageAttachment(
          beaconId: beaconId,
          userId: authorId,
          messageId: saved['id']! as String,
          attachmentBytes: Stream.value(bytes),
          attachmentFilename: name,
          attachmentMimeType: 'text/plain',
        );
      }
    }

    Future<List<String>> attachmentNamesOfKeyedMessages() async {
      final rows = await writer.execute(
        Sql.named('''
SELECT a.file_name
FROM public.beacon_room_message m
JOIN public.beacon_room_message_attachment a ON a.message_id = m.id
WHERE m.beacon_id = @beaconId AND m.client_message_id = @key
ORDER BY a.position
'''),
        parameters: {'beaconId': beaconId, 'key': clientKey},
      );
      return [for (final r in rows) r.first! as String];
    }

    Future<int> keyedMessageCount() async {
      final rows = await writer.execute(
        Sql.named('''
SELECT count(*)::int FROM public.beacon_room_message
WHERE beacon_id = @beaconId AND client_message_id = @key
'''),
        parameters: {'beaconId': beaconId, 'key': clientKey},
      );
      return rows.single.first! as int;
    }

    test('a retry that starts while the first send is still saving its '
        'attachments leaves one message with two attachments', () async {
      storage.holdFirstPut();
      final first = sendWithTwoExtras();
      await storage.firstPutStarted;

      // The first send's answer is lost; the client retries while the
      // first one is still saving its extra attachment.
      final retry = sendWithTwoExtras();
      await retry;
      storage.releaseHeldPut();
      await first;

      expect(await keyedMessageCount(), 1);
      expect(
        await attachmentNamesOfKeyedMessages(),
        unorderedEquals(['van.txt', 'route.txt']),
      );
    }, skip: skipReason);

    test('a retry after the first send finished saving adds no attachment '
        'again', () async {
      await sendWithTwoExtras();
      await sendWithTwoExtras();

      expect(await keyedMessageCount(), 1);
      expect(
        await attachmentNamesOfKeyedMessages(),
        unorderedEquals(['van.txt', 'route.txt']),
      );
    }, skip: skipReason);

    test('two different files picked for one message are both kept', () async {
      await sendWithTwoExtras();

      expect(
        await attachmentNamesOfKeyedMessages(),
        unorderedEquals(['van.txt', 'route.txt']),
      );
    }, skip: skipReason);
  });
}

/// Storage whose first upload can be held open, so a test can start a second
/// send while the first one is still saving.
class _GatedRemoteStorage extends Fake implements RemoteStoragePort {
  Completer<void>? _gate;
  Completer<void> _started = Completer<void>();
  bool _holdNext = false;

  Future<void> get firstPutStarted => _started.future;

  void reset() {
    _gate = null;
    _started = Completer<void>();
    _holdNext = false;
  }

  void holdFirstPut() => _holdNext = true;

  void releaseHeldPut() => _gate?.complete();

  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    await bytes.drain<void>();
    if (_holdNext) {
      _holdNext = false;
      _gate = Completer<void>();
      _started.complete();
      await _gate!.future;
    }
    return path;
  }

  @override
  Future<void> removeObject(String path) async {}
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

class _PgFakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _PgFakeImages extends Fake implements ImageRepositoryPort {}

class _PgFakeTasks extends Fake implements TaskRepositoryPort {}

class _PgFakePolling extends Fake implements PollingRepositoryPort {}

class _PgFakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async => true;
}
