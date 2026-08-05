import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/image_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/noop_commitment_query_case.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';

class _TransactionBeaconRepo implements BeaconRepositoryPort {
  _TransactionBeaconRepo(this.locked);

  BeaconEntity locked;
  final statusTransitions = <_StatusTransitionCall>[];
  int deleteBeaconByIdCalls = 0;
  String? lastDeleteBeaconId;
  String? lastDeleteUserId;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async =>
      locked;

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) =>
      fn(locked);

  @override
  Future<void> deleteBeaconById(String id, {required String userId}) async {
    deleteBeaconByIdCalls++;
    lastDeleteBeaconId = id;
    lastDeleteUserId = userId;
  }

  @override
  Future<void> recordBeaconStatusTransition({
    required String beaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required String reason,
    String? actorId,
  }) async {
    statusTransitions.add(
      _StatusTransitionCall(
        beaconId: beaconId,
        fromStatus: fromStatus,
        toStatus: toStatus,
        reason: reason,
        actorId: actorId,
      ),
    );
    locked = locked.copyWith(status: toStatus);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StatusTransitionCall {
  const _StatusTransitionCall({
    required this.beaconId,
    required this.fromStatus,
    required this.toStatus,
    required this.reason,
    this.actorId,
  });

  final String beaconId;
  final BeaconStatus fromStatus;
  final BeaconStatus toStatus;
  final String reason;
  final String? actorId;
}

class _FakeHelpOfferRepo extends Fake implements HelpOfferRepositoryPort {}

class _TrackingImageRepo extends Fake implements ImageRepositoryPort {
  final deletedImages = <({String authorId, String imageId})>[];

  @override
  Future<int> deleteOwnedRow({
    required String imageId,
    required String authorId,
  }) async {
    deletedImages.add((authorId: authorId, imageId: imageId));
    return 1;
  }
}

class _TrackingImageObjectGc extends Fake implements ImageObjectGcPort {
  final enqueued = <({String authorId, String imageId})>[];

  @override
  Future<void> enqueue({
    required String imageId,
    required String authorId,
  }) async {
    enqueued.add((authorId: authorId, imageId: imageId));
  }
}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

void main() {
  const beaconId = 'B1';
  const helperId = 'Uhelper';
  late _TransactionBeaconRepo beaconRepo;
  late _TrackingImageRepo imageRepo;
  late _TrackingImageObjectGc imageObjectGc;
  late BeaconCase case_;
  final now = DateTime.utc(2026, 6, 25);

  BeaconEntity beacon({
    required BeaconStatus status,
    List<ImageEntity> images = const [],
  }) =>
      BeaconEntity(
        id: beaconId,
        title: 'Title',
        author: const UserEntity(id: 'Uauth'),
        createdAt: now,
        updatedAt: now,
        status: status,
        images: images,
      );

  CommitmentQueryCase commitmentQueryCaseFromEvents(
    List<CommitmentEvent> events,
  ) =>
      CommitmentQueryCase(
        RecordingCommitmentRepository(
          eventsByPair: {
            commitmentPairKey(beaconId, helperId): events,
          },
        ),
        _FakeHelpOfferRepo(),
        env: Env(environment: Environment.test),
        logger: Logger('BeaconCaseDeleteTest'),
      );

  BeaconCase buildCase({CommitmentQueryCase? commitmentQueryCase}) {
    final attention = TestAttentionHarness();
    return BeaconCase(
      beaconRepo,
      imageRepo,
      imageObjectGc,
      _FakeTaskRepo(),
      commitmentQueryCase ?? noopCommitmentQueryCase(),
      FakeBeaconAccessGuard(),
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconCaseDeleteTest'),
    );
  }

  setUp(() {
    beaconRepo = _TransactionBeaconRepo(beacon(status: BeaconStatus.open));
    imageRepo = _TrackingImageRepo();
    imageObjectGc = _TrackingImageObjectGc();
    case_ = buildCase();
  });

  test('deleteById hard-deletes draft beacon and removes images', () async {
    final image = ImageEntity(
      id: 'Img1',
      authorId: 'Uauth',
      createdAt: now,
    );
    beaconRepo.locked = beacon(
      status: BeaconStatus.draft,
      images: [image],
    );

    final result = await case_.deleteById(beaconId: beaconId, userId: 'Uauth');

    expect(result, isTrue);
    expect(imageRepo.deletedImages, [
      (authorId: 'Uauth', imageId: 'Img1'),
    ]);
    expect(imageObjectGc.enqueued, [
      (authorId: 'Uauth', imageId: 'Img1'),
    ]);
    expect(beaconRepo.deleteBeaconByIdCalls, 1);
    expect(beaconRepo.lastDeleteBeaconId, beaconId);
    expect(beaconRepo.lastDeleteUserId, 'Uauth');
    expect(beaconRepo.statusTransitions, isEmpty);
  });

  test('deleteById transitions open beacon to deleted when no committer', () async {
    beaconRepo.locked = beacon(status: BeaconStatus.open);

    final result = await case_.deleteById(beaconId: beaconId, userId: 'Uauth');

    expect(result, isTrue);
    expect(beaconRepo.deleteBeaconByIdCalls, 0);
    expect(beaconRepo.statusTransitions, hasLength(1));
    final transition = beaconRepo.statusTransitions.single;
    expect(transition.beaconId, beaconId);
    expect(transition.fromStatus, BeaconStatus.open);
    expect(transition.toStatus, BeaconStatus.deleted);
    expect(transition.reason, BeaconLifecycleChangeReason.deleted);
    expect(transition.actorId, 'Uauth');
  });

  test('deleteById rejects when a committer was ever acknowledged', () async {
    beaconRepo.locked = beacon(status: BeaconStatus.open);
    case_ = buildCase(
      commitmentQueryCase: commitmentQueryCaseFromEvents([
        CommitmentEvent(
          id: 'CE-1',
          seq: 1,
          beaconId: beaconId,
          userId: helperId,
          actorUserId: 'Uauth',
          kind: CommitmentEventKind.acknowledged,
          reason: null,
          createdAt: now,
        ),
      ]),
    );

    await expectLater(
      case_.deleteById(beaconId: beaconId, userId: 'Uauth'),
      throwsA(
        isA<EvaluationException>().having(
          (e) => e.code.codeNumber,
          'codeNumber',
          const EvaluationExceptionCodes(
            EvaluationExceptionCode.beaconNotClosable,
          ).codeNumber,
        ),
      ),
    );
    expect(beaconRepo.statusTransitions, isEmpty);
    expect(beaconRepo.deleteBeaconByIdCalls, 0);
  });

  test(
    'deleteById rejects after accept then withdraw when commitment history remains',
    () async {
      beaconRepo.locked = beacon(status: BeaconStatus.open);
      case_ = buildCase(
        commitmentQueryCase: commitmentQueryCaseFromEvents([
          CommitmentEvent(
            id: 'CE-1',
            seq: 1,
            beaconId: beaconId,
            userId: helperId,
            actorUserId: 'Uauth',
            kind: CommitmentEventKind.acknowledged,
            reason: null,
            createdAt: now,
          ),
          CommitmentEvent(
            id: 'CE-2',
            seq: 2,
            beaconId: beaconId,
            userId: helperId,
            actorUserId: helperId,
            kind: CommitmentEventKind.withdrawnByHelper,
            reason: null,
            createdAt: now.add(const Duration(hours: 31)),
          ),
        ]),
      );

      await expectLater(
        case_.deleteById(beaconId: beaconId, userId: 'Uauth'),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.description,
            'description',
            'Cannot delete a request that ever had a committer',
          ),
        ),
      );
      expect(beaconRepo.statusTransitions, isEmpty);
      expect(beaconRepo.deleteBeaconByIdCalls, 0);
    },
  );

  test('deleteById rejects disallowed status transition', () async {
    beaconRepo.locked = beacon(status: BeaconStatus.deleted);

    await expectLater(
      case_.deleteById(beaconId: beaconId, userId: 'Uauth'),
      throwsA(
        isA<EvaluationException>().having(
          (e) => e.code.codeNumber,
          'codeNumber',
          const EvaluationExceptionCodes(
            EvaluationExceptionCode.beaconNotClosable,
          ).codeNumber,
        ),
      ),
    );
    expect(beaconRepo.statusTransitions, isEmpty);
    expect(beaconRepo.deleteBeaconByIdCalls, 0);
  });
}
