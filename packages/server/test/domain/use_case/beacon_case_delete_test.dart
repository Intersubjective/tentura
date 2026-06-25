import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/image_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../support/fake_beacon_access_guard.dart';

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

class _StubCoordinationRepo extends Fake implements CoordinationRepositoryPort {
  Future<Map<String, int>> Function()? onCoordinationResponseTypeByOfferUserId;
  int coordinationLookupCalls = 0;

  @override
  Future<Map<String, int>> coordinationResponseTypeByOfferUserId(
    String beaconId,
  ) {
    coordinationLookupCalls++;
    return onCoordinationResponseTypeByOfferUserId!();
  }
}

class _TrackingImageRepo extends Fake implements ImageRepositoryPort {
  final deletedImages = <({String authorId, String imageId})>[];

  @override
  Future<void> delete({
    required String authorId,
    required String imageId,
  }) async {
    deletedImages.add((authorId: authorId, imageId: imageId));
  }
}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

class _FakeHelpOfferRepo extends Fake implements HelpOfferRepositoryPort {}

void main() {
  late _TransactionBeaconRepo beaconRepo;
  late _StubCoordinationRepo coordinationRepo;
  late _TrackingImageRepo imageRepo;
  late BeaconCase case_;
  final now = DateTime.utc(2026, 6, 25);

  BeaconEntity beacon({
    required BeaconStatus status,
    List<ImageEntity> images = const [],
  }) =>
      BeaconEntity(
        id: 'B1',
        title: 'Title',
        author: const UserEntity(id: 'Uauth'),
        createdAt: now,
        updatedAt: now,
        status: status,
        images: images,
      );

  setUp(() {
    beaconRepo = _TransactionBeaconRepo(beacon(status: BeaconStatus.open));
    coordinationRepo = _StubCoordinationRepo();
    imageRepo = _TrackingImageRepo();
    coordinationRepo.onCoordinationResponseTypeByOfferUserId = () async => {};
    case_ = BeaconCase(
      beaconRepo,
      imageRepo,
      _FakeTaskRepo(),
      coordinationRepo,
      _FakeHelpOfferRepo(),
      FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconCaseDeleteTest'),
    );
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

    final result = await case_.deleteById(beaconId: 'B1', userId: 'Uauth');

    expect(result, isTrue);
    expect(imageRepo.deletedImages, [
      (authorId: 'Uauth', imageId: 'Img1'),
    ]);
    expect(beaconRepo.deleteBeaconByIdCalls, 1);
    expect(beaconRepo.lastDeleteBeaconId, 'B1');
    expect(beaconRepo.lastDeleteUserId, 'Uauth');
    expect(beaconRepo.statusTransitions, isEmpty);
    expect(coordinationRepo.coordinationLookupCalls, 0);
  });

  test('deleteById transitions open beacon to deleted when no committer', () async {
    beaconRepo.locked = beacon(status: BeaconStatus.open);

    final result = await case_.deleteById(beaconId: 'B1', userId: 'Uauth');

    expect(result, isTrue);
    expect(beaconRepo.deleteBeaconByIdCalls, 0);
    expect(beaconRepo.statusTransitions, hasLength(1));
    final transition = beaconRepo.statusTransitions.single;
    expect(transition.beaconId, 'B1');
    expect(transition.fromStatus, BeaconStatus.open);
    expect(transition.toStatus, BeaconStatus.deleted);
    expect(transition.reason, BeaconLifecycleChangeReason.deleted);
    expect(transition.actorId, 'Uauth');
    expect(coordinationRepo.coordinationLookupCalls, 1);
  });

  test('deleteById rejects when acknowledged committer existed', () async {
    beaconRepo.locked = beacon(status: BeaconStatus.open);
    coordinationRepo.onCoordinationResponseTypeByOfferUserId = () async => {
          'Uhelper': CoordinationResponseType.useful.smallintValue,
        };

    await expectLater(
      case_.deleteById(beaconId: 'B1', userId: 'Uauth'),
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

  test('deleteById rejects disallowed status transition', () async {
    beaconRepo.locked = beacon(status: BeaconStatus.deleted);

    await expectLater(
      case_.deleteById(beaconId: 'B1', userId: 'Uauth'),
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
