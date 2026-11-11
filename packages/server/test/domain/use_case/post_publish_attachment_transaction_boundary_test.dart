import 'dart:async';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/post_draft_attachment.dart';
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
    test(
      'a draft attachment upload completes before its transaction starts',
      () async {
        final fixture = _Fixture(['attachment']);
        final adding = fixture.addDraftAttachment();
        await fixture.room.uploadStarted.future;
        expect(fixture.unitOfWork.inTransaction, isFalse);
        expect(fixture.events, ['upload started']);

        fixture.room.uploadRelease.complete();
        await fixture.unitOfWork.commitStarted['attachment']!.future;
        expect(fixture.events, [
          'upload started',
          'upload completed',
          'attachment transaction started',
          'post locked',
          'draft attachment saved',
        ]);
        expect(fixture.room.scheduledHashes, isEmpty);
        fixture.unitOfWork.commitRelease['attachment']!.complete();
        await adding;
      },
    );

    test('image hash scheduling waits for the attachment commit', () async {
      final fixture = _Fixture(['attachment']);
      fixture.room.uploadRelease.complete();
      final adding = fixture.addDraftAttachment();
      await fixture.unitOfWork.commitStarted['attachment']!.future;
      expect(fixture.unitOfWork.inTransaction, isTrue);
      expect(fixture.room.scheduledHashes, isEmpty);

      fixture.unitOfWork.commitRelease['attachment']!.complete();
      await adding;
      expect(fixture.room.scheduledHashes, [fixture.room.attachment]);
      expect(fixture.room.hashScheduledInTransaction, isFalse);
      expect(fixture.events.sublist(fixture.events.length - 2), [
        'attachment transaction committed',
        'hash scheduled',
      ]);
    });

    test(
      'publishing hands the saved attachments to the root message inside '
      'the delivery transaction, without uploading or hashing again',
      () async {
        final fixture = _Fixture(['status', 'delivery']);
        fixture.beacons.saved.add((
          id: 'Asaved',
          upload: fixture.room.attachment,
        ));
        final publishing = fixture.publish();
        await fixture.unitOfWork.commitStarted['status']!.future;
        expect(fixture.room.receivedAttachments, isNull);
        fixture.unitOfWork.commitRelease['status']!.complete();
        await fixture.unitOfWork.commitStarted['delivery']!.future;
        expect(fixture.unitOfWork.inTransaction, isTrue);
        expect(fixture.room.receivedAttachments, [fixture.room.attachment]);
        expect(fixture.room.receivedBytes, isNull);
        expect(fixture.events, [
          'status transaction started',
          'post locked',
          'status transaction committed',
          'delivery transaction started',
          'delivery locked',
          'message persisted',
          'draft attachments moved',
          'root persisted',
        ]);

        fixture.unitOfWork.commitRelease['delivery']!.complete();
        final result = await publishing;
        expect(result.rootMessageId, 'root-message');
        expect(fixture.room.uploadStarted.isCompleted, isFalse);
        expect(fixture.room.scheduledHashes, isEmpty);
      },
    );
  });
}

final class _Fixture {
  _Fixture(List<String> phases) {
    unitOfWork = _UnitOfWork(events, phases);
    room = _Room(unitOfWork, events);
    beacons = _Beacons(events);
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
  late final _Beacons beacons;
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
  );

  Future<String> addDraftAttachment() => post.addDraftAttachment(
    authorId: 'author',
    beaconId: 'post',
    bytes: Stream.value(Uint8List.fromList([1, 2, 3])),
    filename: 'photo.jpg',
    mimeType: 'image/jpeg',
  );
}

final class _UnitOfWork extends Fake implements MutatingUnitOfWorkPort {
  _UnitOfWork(this.events, this.phases)
    : commitStarted = {for (final phase in phases) phase: Completer<void>()},
      commitRelease = {for (final phase in phases) phase: Completer<void>()};
  final List<String> events;

  /// Names of the transactions expected, in order.
  final List<String> phases;
  final Map<String, Completer<void>> commitStarted;
  final Map<String, Completer<void>> commitRelease;
  var _transactions = 0;
  bool inTransaction = false;

  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) async {
    expect(inTransaction, isFalse);
    if (_transactions == phases.length) {
      throw StateError('Unexpected transaction');
    }
    final phase = phases[_transactions++];
    inTransaction = true;
    events.add('$phase transaction started');
    try {
      final value = await action();
      commitStarted[phase]!.complete();
      await commitRelease[phase]!.future;
      events.add('$phase transaction committed');
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
  List<UploadedRoomAttachment>? receivedAttachments;
  Stream<Uint8List>? receivedBytes;
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
    List<UploadedRoomAttachment> savedAttachments = const [],
    List<String> explicitMentionUserIds = const [],
    List<int> explicitMentionOffsets = const [],
    List<int> explicitMentionLengths = const [],
    String? quotedFactCardId,
    int? quotedFactRevisionSeq,
    Set<String> suppressMentionNotifyFor = const {},
    String? clientMessageId,
  }) async {
    receivedAttachments = savedAttachments;
    receivedBytes = attachmentBytes;
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
  BeaconEntity _post = _draft();
  final saved = <PostDraftAttachment>[];

  @override
  Future<List<PostDraftAttachment>> postDraftAttachments(
    String beaconId,
  ) async => List.of(saved);

  @override
  Future<String> insertPostDraftAttachment({
    required String beaconId,
    required UploadedRoomAttachment upload,
  }) async {
    saved.add((id: 'A${saved.length}', upload: upload));
    events.add('draft attachment saved');
    return saved.last.id;
  }

  @override
  Future<void> deletePostDraftAttachments(String beaconId) async {
    saved.clear();
    events.add('draft attachments moved');
  }

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async => _post;

  @override
  Future<BeaconEntity> publishDraft({
    required String id,
    required String actorId,
  }) async => _post = _post.copyWith(status: BeaconStatus.open);

  @override
  Future<void> setForwardPolicy({
    required String beaconId,
    required BeaconForwardPolicyValue policy,
  }) async {}

  @override
  Future<int?> postDraftLifetimeHours(String beaconId) async => null;

  @override
  Future<void> clearPostDraftComposerFields(String beaconId) async {}

  @override
  Future<void> setPostRootMessage({
    required String beaconId,
    required String messageId,
  }) async {
    _post = _post.copyWith(postRootMessageId: messageId);
    events.add('root persisted');
  }

  @override
  Future<DateTime?> postExpiresAt(String postId) async =>
      DateTime.utc(2026, 1, 3);
}

final class _PostLock extends Fake implements PostLockPort {
  _PostLock(this.events);
  final List<String> events;

  @override
  Future<void> lockForPostMutation(String beaconId) async {
    events.add('post locked');
  }

  @override
  Future<void> lockForPostDelivery(
    String beaconId, {
    required String senderId,
  }) async {
    events.add('delivery locked');
  }
}

final class _UnusedDispatch extends Fake implements AttentionDispatchPort {}

final class _UnusedImages extends Fake implements ImageRepositoryPort {}

final class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

final class _UnusedTasks extends Fake implements TaskRepositoryPort {}

final class _UnusedCommitments extends Fake
    implements CommitmentRepositoryPort {}

final class _UnusedOutbox extends Fake implements BeaconHierarchyOutboxPort {}
