@Tags(['pg'])
library;

import 'dart:async';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/tasks_repository.dart';
import 'package:tentura_server/data/repository/upload_quota_repository.dart';
import 'package:tentura_server/data/service/task_worker.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/pg_wait.dart';
import '../../support/test_attention_harness.dart';

const _beaconId = 'Battachcommit01';
const _authorId = 'Uattachauthor01';
const _peerId = 'Uattachpeer01';
const _replyId = 'Rattachreply01';
final _jpegBytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]);

void main() {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_ATTACHMENT_COMMIT_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_attachment_commit',
  );
  late DisposablePgWriterSession session;
  late Connection dbConnection;
  late TaskWorker worker;
  late TenturaDb database;
  late _Transactions transactions;
  final closeResources = <Future<void> Function()>[];

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    closeResources.add(() => tearDownDisposablePgWriter(session: session));
    dbConnection = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    transactions = _Transactions();
    closeResources.add(dbConnection.close);
    database = TenturaDb.forTest(
      database: PgDatabase.opened(
        dbConnection,
        enableMigrations: false,
      ).interceptWith(transactions),
    );
    transactions.imageTableName = database.images.actualTableName;
    closeResources.add(database.close);
    worker = TaskWorker(
      await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      ),
    );
    closeResources.add(worker.dispose);
    await worker.init();
  });

  tearDownAll(() async {
    for (final close in closeResources.reversed) {
      await close();
    }
  });

  setUp(() async {
    await session.writer.execute(
      'TRUNCATE TABLE public.tasks, public.beacon, public."user" CASCADE',
    );
    for (final (index, id) in [_authorId, _peerId].indexed) {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('attachmentcommit', index + 1),
        },
      );
    }
    await session.writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$_beaconId', '$_authorId', 'Attachments', '', 0, now())
''');
    await session.writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_replyId', '$_beaconId', '$_peerId', 'Original message')
''');
    transactions.imageWrites.clear();
  });

  _Fixture fixture({
    bool blockUpload = false,
    bool blockDispatch = false,
    bool abortBeforeCommit = false,
  }) => _Fixture(
    database: database,
    target: target,
    worker: worker,
    blockUpload: blockUpload,
    blockDispatch: blockDispatch,
    abortBeforeCommit: abortBeforeCommit,
  );

  group('Room attachment upload and commit visibility', () {
    for (final isImage in [false, true]) {
      final kind = isImage ? 'image' : 'file';
      test(
        'blocked $kind upload permits a read on the same Drift connection',
        () async {
          final f = fixture(blockUpload: true);
          final send = f.send(isImage: isImage);
          final sent = expectLater(send, completes);
          try {
            await f.storage.started.future.timeout(kStableStateWait);
            expect(f.storage.release.isCompleted, isFalse);
            // Start the read outside the sending action's transaction zone.
            final read = database.customSelect('SELECT 1 AS value').getSingle();
            final completed = await read
                .then((_) => true)
                .timeout(
                  kCompletionWait,
                  onTimeout: () => false,
                );
            expect(
              completed,
              isTrue,
              reason: 'The real Drift lane must remain usable while S3 blocks',
            );
            expect(
              transactions.active,
              isEmpty,
              reason: 'No repository transaction may span the S3 round trip',
            );
            if (isImage) {
              expect(
                transactions.imageWrites.intersection(transactions.active),
                isEmpty,
                reason:
                    'Image-row DB work must not hold an open transaction '
                    'across object-store I/O',
              );
            }
          } finally {
            f.storage.release.complete();
            await sent;
          }
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }

    test('hash worker sees image work only after message commit', () async {
      final f = fixture(blockDispatch: true);
      final send = f.send(isImage: true);
      final sent = expectLater(send, completes);
      try {
        await f.dispatch.started.future.timeout(kStableStateWait);
        expect(transactions.active, isNotEmpty);
        expect(await _replyCount(session.writer), 0);
        // This is the real TaskWorker on its own PostgreSQL connection. Enqueue
        // on Drift's transaction is allowed, but must remain invisible here.
        final premature = await f.tasks
            .acquire<TaskEntity<TaskCalculateImageHashDetails>>();
        expect(
          premature,
          isNull,
          reason: 'Hash work must not be acquired before the message commits',
        );
      } finally {
        f.dispatch.release.complete();
        await sent;
      }
      final task = await f.tasks
          .acquire<TaskEntity<TaskCalculateImageHashDetails>>();
      expect(task, isNotNull);
      final image = await session.writer.execute(
        Sql.named('SELECT id FROM public.image WHERE id = @id::uuid'),
        parameters: {'id': task!.details.imageId},
      );
      expect(
        image,
        hasLength(1),
        reason: 'The hash worker must be able to load the committed image row',
      );
      final attachments = await session.writer.execute(
        Sql.named('''
SELECT a.id FROM public.beacon_room_message_attachment a
JOIN public.beacon_room_message m ON m.id = a.message_id
WHERE m.reply_to_message_id = @reply AND a.image_id = @image::uuid
'''),
        parameters: {'reply': _replyId, 'image': task.details.imageId},
      );
      expect(attachments, hasLength(1));
      expect(await _replyCount(session.writer), 1);
    });

    test(
      'rollback after the completed image action leaves no durable hash job',
      () async {
        final f = fixture(abortBeforeCommit: true);
        await expectLater(
          f.send(isImage: true),
          throwsA(same(f.unitOfWork.failure)),
        );
        // The abort hook runs AFTER the whole persistence action (and any enqueue)
        // returns, not inside dispatch or before attachment/task writes.
        expect(f.unitOfWork.completedAction, isTrue);
        expect(f.unitOfWork.attachmentsAtAbort, 1);
        expect(f.unitOfWork.messageIdAtAbort, isNotEmpty);
        expect(transactions.active, isEmpty);
        expect(await _replyCount(session.writer), 0);
        final jobs = await session.writer.execute(
          "SELECT id FROM public.tasks WHERE queue = 'calculate_image_hash'",
        );
        expect(
          jobs,
          isEmpty,
          reason:
              'Jobs enqueued before rollback must disappear, including '
              '${f.unitOfWork.jobIdsAtAbort}; after-commit scheduling must not run',
        );
        expect(
          await f.tasks.acquire<TaskEntity<TaskCalculateImageHashDetails>>(),
          isNull,
        );
      },
    );
  });
}

Future<int> _replyCount(Connection observer) async =>
    (await observer.execute(
          Sql.named('''
SELECT count(*)::int FROM public.beacon_room_message
WHERE reply_to_message_id = @reply
'''),
          parameters: {'reply': _replyId},
        )).single.single!
        as int;

/// Records real Drift transactions, including ones opened inside ImageRepository.
class _Transactions extends QueryInterceptor {
  final active = <TransactionExecutor>{};
  final imageWrites = <TransactionExecutor>{};
  late String imageTableName;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    final transaction = super.beginTransaction(parent);
    active.add(transaction);
    return transaction;
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    try {
      await super.commitTransaction(inner);
    } finally {
      active.remove(inner);
    }
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    try {
      await super.rollbackTransaction(inner);
    } finally {
      active.remove(inner);
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (executor is TransactionExecutor &&
        statement.toLowerCase().contains('insert into "$imageTableName"')) {
      imageWrites.add(executor);
    }
    return super.runSelect(executor, statement, args);
  }
}

class _Storage extends Fake implements RemoteStoragePort {
  _Storage({required this.blockUpload});
  final bool blockUpload;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    await bytes.drain<void>();
    started.complete();
    if (blockUpload) await release.future;
    return path;
  }
}

class _Dispatch extends Fake implements AttentionDispatchPort {
  _Dispatch({required this.blockDispatch});
  final bool blockDispatch;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> record(AttentionDispatchIntent intent) async {
    started.complete();
    if (blockDispatch) await release.future;
  }
}

class _UnitOfWork extends Fake implements MutatingUnitOfWorkPort {
  _UnitOfWork(this.database, {required this.abortBeforeCommit});
  final TenturaDb database;
  final bool abortBeforeCommit;
  final failure = StateError(
    'Reject completed message transaction before commit',
  );
  bool completedAction = false;
  String? messageIdAtAbort;
  int? attachmentsAtAbort;
  List<Object?> jobIdsAtAbort = const [];

  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) => MutatingUnitOfWork(database).run(
    actorUserId: actorUserId,
    action: () async {
      final result = await action();
      if (abortBeforeCommit) {
        completedAction = true;
        messageIdAtAbort = (result as Map<String, Object?>)['id']! as String;
        attachmentsAtAbort =
            (await database
                    .customSelect(
                      r'''
SELECT count(*)::int AS c FROM public.beacon_room_message_attachment
WHERE message_id = $1
''',
                      variables: [Variable<String>(messageIdAtAbort)],
                    )
                    .getSingle())
                .read<int>('c');
        // Read using the sending connection, so both independently committed
        // jobs and jobs still inside the transaction are witnessed.
        jobIdsAtAbort = [
          for (final row
              in await database
                  .customSelect(
                    "SELECT id FROM public.tasks WHERE queue = 'calculate_image_hash'",
                  )
                  .get())
            row.data['id'],
        ];
        throw failure;
      }
      return result;
    },
  );
}

class _Items extends Fake implements CoordinationItemRepositoryPort {}

class _FactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _Polling extends Fake implements PollingRepositoryPort {}

class _Fixture {
  _Fixture({
    required TenturaDb database,
    required DisposablePgTarget target,
    required TaskWorker worker,
    required bool blockUpload,
    required bool blockDispatch,
    required bool abortBeforeCommit,
  }) {
    storage = _Storage(blockUpload: blockUpload);
    dispatch = _Dispatch(blockDispatch: blockDispatch);
    unitOfWork = _UnitOfWork(database, abortBeforeCommit: abortBeforeCommit);
    tasks = TaskRepository(worker);
    final quota = UploadQuotaRepository(database);
    sut = BeaconRoomCase(
      BeaconRoomRepository(database),
      _Items(),
      _FactCards(),
      ImageRepository(
        database,
        storage,
        quota,
        ImageObjectGcRepository(database, storage),
        target.databaseEnv,
        Logger('RoomAttachmentCommitVisibilityTest'),
      ),
      tasks,
      storage,
      _Polling(),
      quota,
      FakeUserBlockRepository(),
      unitOfWork,
      FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
      attention: TransactionalAttentionCase(unitOfWork, dispatch),
      attentionIntents: TestAttentionHarness().intents,
      env: target.databaseEnv,
      logger: Logger('RoomAttachmentCommitVisibilityTest'),
    );
  }
  late final _Storage storage;
  late final _Dispatch dispatch;
  late final _UnitOfWork unitOfWork;
  late final TaskRepository tasks;
  late final BeaconRoomCase sut;

  Future<Map<String, Object?>> send({required bool isImage}) =>
      sut.createMessage(
        beaconId: _beaconId,
        userId: _authorId,
        body: 'Reply with attachment',
        replyToMessageId: _replyId,
        attachmentBytes: Stream.value(
          isImage
              ? _jpegBytes
              : Uint8List.fromList('plain file contents'.codeUnits),
        ),
        attachmentFilename: isImage ? 'photo.jpg' : 'notes.txt',
        attachmentMimeType: isImage ? 'image/jpeg' : 'text/plain',
      );
}
