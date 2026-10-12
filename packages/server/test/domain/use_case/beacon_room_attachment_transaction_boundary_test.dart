import 'dart:async';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:pg_job_queue/pg_job_queue.dart' show Job, JobStatus;
import 'package:tentura_server/data/repository/tasks_repository.dart';
import 'package:tentura_server/data/service/task_worker.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/test_attention_harness.dart';

const _beaconId = 'Baaaaaaaaaaaa';
const _authorId = 'Uaaaaaaaaaaaa';
const _recipientId = 'Ubbbbbbbbbbbb';
const _replyId = 'Rbbbbbbbbbbbb';
const _messageId = 'Raaaaaaaaaaaa';
const _imageId = '00000000-0000-4000-8000-000000000001';
final _imageBytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]);

void main() {
  group('Room attachment transaction boundaries', () {
    for (final isImage in [false, true]) {
      final kind = isImage ? 'image' : 'file';
      test(
        'blocked $kind upload leaves the DB lane available for a plain read',
        () async {
          final fixture = _Fixture(blockUpload: true);
          final send = fixture.send(isImage: isImage);
          // Attach an error handler before awaiting the upload barrier.
          final sent = expectLater(send, completes);
          try {
            await fixture.storage.started.future.timeout(
              const Duration(seconds: 2),
            );
            expect(fixture.storage.putPaths, hasLength(1));
            expect(fixture.storage.release.isCompleted, isFalse);
            expect(
              fixture.database.imageRowHeldAcrossUpload,
              isFalse,
              reason:
                  'An image-row write must not keep its transaction open '
                  'during object-store I/O',
            );

            // This read is outside the sending action, on the same isolate/lane.
            // It must finish while S3 is still blocked, not after releasing S3.
            final read = fixture.database.plainRead();
            final readCompleted = await read
                .then((_) => true)
                .timeout(
                  const Duration(milliseconds: 100),
                  onTimeout: () => false,
                );
            expect(
              readCompleted,
              isTrue,
              reason: 'An object-store upload must not hold the DB lane',
            );
            expect(fixture.storage.uploadStartedInTransaction, isFalse);
          } finally {
            fixture.storage.release.complete();
            await sent;
          }
          expect(fixture.database.messages, contains(_messageId));
          expect(fixture.database.attachments, contains(_messageId));
        },
      );
    }

    test(
      'image hash work becomes available only after its rows commit',
      () async {
        final fixture = _Fixture(blockDispatch: true);
        final send = fixture.send(isImage: true);
        final sent = expectLater(send, completes);
        try {
          // Hold receipt persistence immediately before the transaction commits.
          await fixture.dispatch.started.future.timeout(
            const Duration(seconds: 2),
          );
          expect(fixture.database.inTransaction, isTrue);
          expect(fixture.database.messages, isEmpty);
          expect(fixture.database.attachments, isEmpty);
          final available = await fixture.tasks
              .acquire<TaskEntity<TaskCalculateImageHashDetails>>();
          expect(
            available,
            isNull,
            reason: 'The independent hash worker must not see uncommitted work',
          );
        } finally {
          fixture.dispatch.release.complete();
          await sent;
        }

        final task = await fixture.tasks
            .acquire<TaskEntity<TaskCalculateImageHashDetails>>();
        expect(task, isNotNull);
        expect(task!.details.imageId, _imageId);
        expect(fixture.database.images, contains(task.details.imageId));
        expect(fixture.database.messages, contains(_messageId));
        expect(fixture.database.attachments, contains(_messageId));
        expect(
          fixture.worker.workerSawInvisibleImage,
          isFalse,
          reason: 'Hashing must never start before its image row is visible',
        );
      },
    );

    test(
      'rolling back an image message leaves no scheduled hash work',
      () async {
        final fixture = _Fixture(abortBeforeCommit: true);
        await expectLater(
          fixture.send(isImage: true),
          throwsA(same(fixture.database.failure)),
        );

        // Abort after the complete action returns, including any transactional
        // enqueue. After-commit scheduling is also valid: that path never runs.
        expect(fixture.storage.putPaths, hasLength(1));
        expect(fixture.room.insertedAttachment, isTrue);
        expect(fixture.database.actionCompletedBeforeRollback, isTrue);
        expect(fixture.database.rollbacks, 1);
        expect(fixture.database.messages, isEmpty);
        expect(fixture.database.attachments, isEmpty);
        expect(
          fixture.worker.scheduled,
          isEmpty,
          reason: 'Durable hash jobs must not survive the message rollback',
        );
        expect(
          await fixture.tasks
              .acquire<TaskEntity<TaskCalculateImageHashDetails>>(),
          isNull,
        );
      },
    );
  });
}

/// Models the isolate's serial DB lane and visibility from a worker connection.
/// Writes in a transaction publish together on commit and disappear on rollback.
class _DatabaseLane extends Fake implements MutatingUnitOfWorkPort {
  _DatabaseLane({this.abortBeforeCommit = false});

  final bool abortBeforeCommit;
  final failure = StateError('Message transaction rejected before commit');
  final messages = <String>{};
  final attachments = <String>{};
  final images = <String>{};
  final _pending = <void Function()>[];
  Completer<void>? _transactionDone;
  int rollbacks = 0;
  bool actionCompletedBeforeRollback = false;
  bool imageRowHeldAcrossUpload = false;

  bool get inTransaction => _transactionDone != null;

  void write(void Function() publish) {
    if (inTransaction) {
      _pending.add(publish);
    } else {
      publish();
    }
  }

  Future<int> plainRead() async {
    final transactionDone = _transactionDone;
    if (transactionDone != null) await transactionDone.future;
    return messages.length;
  }

  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) async {
    if (inTransaction) throw StateError('Unexpected nested transaction');
    _transactionDone = Completer<void>();
    try {
      final result = await action();
      if (abortBeforeCommit) {
        actionCompletedBeforeRollback = true;
        throw failure;
      }
      for (final publish in _pending) {
        publish();
      }
      return result;
    } on Object {
      rollbacks++;
      rethrow;
    } finally {
      _pending.clear();
      final transactionDone = _transactionDone!;
      _transactionDone = null;
      transactionDone.complete();
    }
  }
}

class _Storage extends Fake implements RemoteStoragePort {
  _Storage(this.database, {required this.blockUpload});

  final _DatabaseLane database;
  final bool blockUpload;
  final started = Completer<void>();
  final release = Completer<void>();
  final putPaths = <String>[];
  bool? uploadStartedInTransaction;

  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    await bytes.drain<void>();
    putPaths.add(path);
    uploadStartedInTransaction = database.inTransaction;
    started.complete();
    if (blockUpload) await release.future;
    return path;
  }
}

class _Images extends Fake implements ImageRepositoryPort {
  _Images(this.database, this.storage);
  final _DatabaseLane database;
  final _Storage storage;

  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async {
    // ImageRepository creates its row before awaiting putObject.
    database
      ..write(() => database.images.add(_imageId))
      ..imageRowHeldAcrossUpload = database.inTransaction;
    await storage.putObject('images/$authorId/$_imageId.jpg', bytes);
    return _imageId;
  }
}

/// Models TaskWorker's independent connection, not the room repository port.
/// The real TaskRepository decides whether to write through this worker; writes
/// here commit independently, as they do on TaskWorker's PostgreSQL connection.
/// The PG companion also covers enqueueing on Drift's connection instead.
class _IndependentTaskWorker extends Fake implements TaskWorker {
  _IndependentTaskWorker(this.database);
  final _DatabaseLane database;
  final scheduled = <Job>[];
  final _available = <Job>[];
  bool workerSawInvisibleImage = false;

  @override
  Future<String> schedule(
    Map<String, Object?> payload, {
    String? queue,
    int priority = 0,
  }) async {
    final job = Job(
      'hash-task',
      queue!,
      payload,
      JobStatus.scheduled,
      priority: priority,
    );
    scheduled.add(job);
    _available.add(job);
    return job.id;
  }

  @override
  Future<Job?> acquire({String? queue, String? worker}) async {
    if (_available.isEmpty) return null;
    final job = _available.removeAt(0);
    expect(job.queue, queue);
    final details = TaskCalculateImageHashDetails.fromJson(job.payload);
    if (!database.images.contains(details.imageId)) {
      workerSawInvisibleImage = true;
    }
    return Job(
      job.id,
      job.queue,
      job.payload,
      JobStatus.acquired,
      worker: worker,
      priority: job.priority,
    );
  }
}

class _Dispatch extends Fake implements AttentionDispatchPort {
  _Dispatch({required this.blockDispatch, required this.failDispatch});
  final bool blockDispatch;
  final bool failDispatch;
  final started = Completer<void>();
  final release = Completer<void>();
  final failure = StateError('Receipt persistence rejected');

  @override
  Future<void> record(AttentionDispatchIntent intent) async {
    started.complete();
    if (blockDispatch) await release.future;
    if (failDispatch) throw failure;
  }
}

class _Room extends Fake implements BeaconRoomRepositoryPort {
  _Room(this.database);
  final _DatabaseLane database;
  bool insertedAttachment = false;

  @override
  Future<String?> beaconAuthorUserId(String beaconId) async => _authorId;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async => true;

  @override
  Future<int> countRecentMessagesByAuthor({
    required String authorId,
    required Duration window,
  }) async => 0;

  @override
  Future<List<AdmittedRoomMentionParticipant>> listAdmittedMentionParticipants(
    String beaconId,
  ) async => const [];

  @override
  Future<List<String>> resolveMentionUserIdsForBeacon({
    required String beaconId,
    required String body,
  }) async => const [];

  @override
  Future<BeaconRoomMessageRecord?> getRoomMessageById(String id) async =>
      BeaconRoomMessageRecord(
        id: _replyId,
        beaconId: _beaconId,
        authorId: _recipientId,
        createdAt: DateTime.utc(2026),
      );

  @override
  Future<BeaconRoomMessageRecord> insertRoomMessage({
    required String beaconId,
    required String authorId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    String? linkedParticipantId,
    String? linkedPollingId,
    int? semanticMarker,
    Map<String, Object?>? systemPayload,
    List<String> mentions = const [],
    List<Map<String, Object?>> mentionSpans = const [],
    String? quotedFactCardId,
    int? quotedFactRevisionSeq,
  }) async {
    database.write(() => database.messages.add(_messageId));
    return BeaconRoomMessageRecord(
      id: _messageId,
      beaconId: beaconId,
      authorId: authorId,
      body: body,
      replyToMessageId: replyToMessageId,
      createdAt: DateTime.utc(2026),
    );
  }

  @override
  Future<int> countAttachmentsForMessage(String messageId) async => 0;

  @override
  Future<void> insertRoomMessageAttachmentImage({
    required String attachmentId,
    required String messageId,
    required int position,
    required String imageId,
    required String mime,
    required int sizeBytes,
    required String displayName,
    required String mutatingUserId,
  }) async {
    insertedAttachment = true;
    database.write(() => database.attachments.add(messageId));
  }

  @override
  Future<void> insertRoomMessageAttachmentFile({
    required String attachmentId,
    required String messageId,
    required int position,
    required String storagePath,
    required String mime,
    required int sizeBytes,
    required String displayName,
    required String mutatingUserId,
  }) async {
    insertedAttachment = true;
    database.write(() => database.attachments.add(messageId));
  }
}

class _Quota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async => true;
}

class _Items extends Fake implements CoordinationItemRepositoryPort {}

class _FactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _Polling extends Fake implements PollingRepositoryPort {}

class _Fixture {
  _Fixture({
    bool blockUpload = false,
    bool blockDispatch = false,
    bool failDispatch = false,
    bool abortBeforeCommit = false,
  }) : database = _DatabaseLane(abortBeforeCommit: abortBeforeCommit) {
    storage = _Storage(database, blockUpload: blockUpload);
    room = _Room(database);
    worker = _IndependentTaskWorker(database);
    tasks = TaskRepository(worker);
    dispatch = _Dispatch(
      blockDispatch: blockDispatch,
      failDispatch: failDispatch,
    );
    sut = BeaconRoomCase(
      room,
      _Items(),
      _FactCards(),
      _Images(database, storage),
      tasks,
      storage,
      _Polling(),
      _Quota(),
      FakeUserBlockRepository(),
      database,
      FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
      attention: TransactionalAttentionCase(database, dispatch),
      attentionIntents: TestAttentionHarness().intents,
      env: Env(environment: Environment.test),
      logger: Logger('RoomAttachmentTransactionBoundaryTest'),
    );
  }

  final _DatabaseLane database;
  late final _Storage storage;
  late final _Room room;
  late final _IndependentTaskWorker worker;
  late final TaskRepository tasks;
  late final _Dispatch dispatch;
  late final BeaconRoomCase sut;

  Future<Map<String, Object?>> send({required bool isImage}) =>
      sut.createMessage(
        beaconId: _beaconId,
        userId: _authorId,
        body: 'Attached reply',
        replyToMessageId: _replyId,
        attachmentBytes: Stream.value(
          isImage
              ? _imageBytes
              : Uint8List.fromList('attachment content'.codeUnits),
        ),
        attachmentFilename: isImage ? 'photo.jpg' : 'notes.txt',
        attachmentMimeType: isImage ? 'image/jpeg' : 'text/plain',
      );
}
