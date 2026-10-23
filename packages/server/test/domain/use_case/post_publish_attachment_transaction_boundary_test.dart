import 'dart:async';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/post_publish_result.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import 'forward_case_mocks.mocks.dart';

void main() {
  group('Post attachment transaction boundaries', () {
    test('upload completes before the publishing transaction starts', () async {
      final fixture = _Fixture();
      final publishing = fixture.publish();
      await fixture.room.uploadStarted.future;
      expect(fixture.unitOfWork.inTransaction, isFalse);
      expect(fixture.events, ['upload started']);

      fixture.room.uploadRelease.complete();
      await fixture.unitOfWork.commitStarted.future;
      expect(fixture.events, [
        'upload started',
        'upload completed',
        'transaction started',
        'post locked',
        'message persisted',
        'root persisted',
      ]);
      fixture.unitOfWork.commitRelease.complete();
      await publishing;
    });

    test('image hash scheduling waits for the outer publish commit', () async {
      final fixture = _Fixture();
      fixture.room.uploadRelease.complete();
      final publishing = fixture.publish();
      await fixture.unitOfWork.commitStarted.future;
      expect(fixture.unitOfWork.inTransaction, isTrue);
      expect(fixture.room.scheduledHashes, isEmpty);
      expect(fixture.room.receivedAttachment, fixture.room.attachment);
      expect(fixture.room.receivedBytes, isNull);
      expect(fixture.room.deferHash, isTrue);

      fixture.unitOfWork.commitRelease.complete();
      final result = await publishing;
      expect(result.rootMessageId, 'root-message');
      expect(fixture.room.scheduledHashes, [fixture.room.attachment]);
      expect(fixture.room.hashScheduledInTransaction, isFalse);
      expect(fixture.events.sublist(fixture.events.length - 2), [
        'transaction committed',
        'hash scheduled',
      ]);
    });
  });
}

final class _Fixture {
  _Fixture() {
    unitOfWork = _UnitOfWork(events);
    room = _Room(unitOfWork, events);
    final beacons = _Beacons(events);
    final env = Env(environment: Environment.test);
    final logger = Logger('PostAttachmentTransactionBoundaries');
    final helpOffers = MockHelpOfferRepositoryPort();
    final guard = FakeBeaconAccessGuard();
    post = PostCase(
      forwardCase: ForwardCase(
        MockForwardEdgeRepositoryPort(),
        MockForwardAttributionRepositoryPort(),
        helpOffers,
        MockInboxRepositoryPort(),
        MockCapabilityEvidencePort(),
        beacons,
        FakeUserBlockRepository(),
        MockPersonVisibilityRepositoryPort(),
        guard,
        env: env,
        logger: logger,
      ),
      roomCase: room,
      beaconRepository: beacons,
      postLock: _PostLock(events),
      attention: TransactionalAttentionCase(unitOfWork, _UnusedDispatch()),
      beaconCase: BeaconCase(
        beacons,
        _UnusedImages(),
        _UnusedImageGc(),
        _UnusedTasks(),
        CommitmentQueryCase(
          _UnusedCommitments(),
          helpOffers,
          env: env,
          logger: logger,
        ),
        guard,
        FakeBeaconHierarchyRepository(),
        FakeBeaconChildCreatePort(),
        BeaconLifecycleEffectsCase(
          _UnusedOutbox(),
          env: env,
          logger: logger,
        ),
        env: env,
        logger: logger,
      ),
    );
  }

  final events = <String>[];
  late final _UnitOfWork unitOfWork;
  late final _Room room;
  late final PostCase post;

  Future<PostPublishResult> publish() => post.publish(
    authorId: 'author',
    beaconId: 'post',
    body: 'Photo',
    mentionUserIds: const [],
    mentionOffsets: const [],
    mentionLengths: const [],
    recipientIds: const [],
    notes: const {},
    forwardPolicy: BeaconForwardPolicyValue.open,
    attachmentBytes: Stream.value(Uint8List.fromList([1, 2, 3])),
    attachmentFilename: 'photo.jpg',
    attachmentMimeType: 'image/jpeg',
  );
}

final class _UnitOfWork extends Fake implements MutatingUnitOfWorkPort {
  _UnitOfWork(this.events);
  final List<String> events;
  final commitStarted = Completer<void>();
  final commitRelease = Completer<void>();
  bool inTransaction = false;

  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) async {
    inTransaction = true;
    events.add('transaction started');
    try {
      final value = await action();
      commitStarted.complete();
      await commitRelease.future;
      events.add('transaction committed');
      return value;
    } finally {
      inTransaction = false;
    }
  }
}

final class _Room extends Fake implements BeaconRoomCase {
  _Room(this.unitOfWork, this.events);
  final _UnitOfWork unitOfWork;
  final List<String> events;
  final uploadStarted = Completer<void>();
  final uploadRelease = Completer<void>();
  final UploadedRoomAttachment attachment = (
    imageId: 'image',
    storagePath: null,
    mime: 'image/jpeg',
    sizeBytes: 3,
    displayName: 'photo.jpg',
  );
  final scheduledHashes = <UploadedRoomAttachment?>[];
  UploadedRoomAttachment? receivedAttachment;
  Stream<Uint8List>? receivedBytes;
  bool? deferHash;
  bool? hashScheduledInTransaction;

  @override
  Future<UploadedRoomAttachment?> prepareMessageAttachment({
    required String userId,
    required Stream<Uint8List> bytes,
    String? uploadFilename,
    String? uploadMimeType,
  }) async {
    await bytes.drain<void>();
    events.add('upload started');
    uploadStarted.complete();
    await uploadRelease.future;
    events.add('upload completed');
    return attachment;
  }

  @override
  Future<Map<String, Object?>> createMessage({
    required String beaconId,
    required String userId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    Stream<Uint8List>? attachmentBytes,
    String? attachmentFilename,
    String? attachmentMimeType,
    UploadedRoomAttachment? uploadedAttachment,
    bool deferAttachmentHash = false,
    List<String> explicitMentionUserIds = const [],
    List<int> explicitMentionOffsets = const [],
    List<int> explicitMentionLengths = const [],
    String? quotedFactCardId,
    int? quotedFactRevisionSeq,
    Set<String> suppressMentionNotifyFor = const {},
    String? clientMessageId,
  }) async {
    receivedAttachment = uploadedAttachment;
    receivedBytes = attachmentBytes;
    deferHash = deferAttachmentHash;
    events.add('message persisted');
    return {'id': 'root-message', 'beaconId': beaconId};
  }

  @override
  Future<void> scheduleAttachmentHash(
    UploadedRoomAttachment? attachment,
  ) async {
    hashScheduledInTransaction = unitOfWork.inTransaction;
    scheduledHashes.add(attachment);
    events.add('hash scheduled');
  }
}

BeaconEntity _draft() => BeaconEntity(
  id: 'post',
  title: 'Photo',
  author: const UserEntity(id: 'author'),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  kind: BeaconKind.post,
  status: BeaconStatus.draft,
);

final class _Beacons extends Fake implements BeaconRepositoryPort {
  _Beacons(this.events);
  final List<String> events;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async => _draft();

  @override
  Future<BeaconEntity> publishDraft({
    required String id,
    required String actorId,
  }) async => _draft();

  @override
  Future<void> setForwardPolicy({
    required String beaconId,
    required BeaconForwardPolicyValue policy,
  }) async {}

  @override
  Future<void> setPostRootMessage({
    required String beaconId,
    required String messageId,
  }) async {
    events.add('root persisted');
  }
}

final class _PostLock extends Fake implements PostLockPort {
  _PostLock(this.events);
  final List<String> events;

  @override
  Future<void> lockForPostMutation(String beaconId) async {
    events.add('post locked');
  }
}

final class _UnusedDispatch extends Fake implements AttentionDispatchPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

final class _UnusedTasks extends Fake implements TaskRepositoryPort {}

final class _UnusedCommitments extends Fake
    implements CommitmentRepositoryPort {}

final class _UnusedOutbox extends Fake implements BeaconHierarchyOutboxPort {}
