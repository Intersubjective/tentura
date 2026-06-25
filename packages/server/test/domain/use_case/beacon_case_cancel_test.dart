import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
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

@immutable
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

  @override
  bool operator ==(Object other) =>
      other is _StatusTransitionCall &&
      other.beaconId == beaconId &&
      other.fromStatus == fromStatus &&
      other.toStatus == toStatus &&
      other.reason == reason &&
      other.actorId == actorId;

  @override
  int get hashCode =>
      Object.hash(beaconId, fromStatus, toStatus, reason, actorId);
}

class _TransactionStubBeaconRepo implements BeaconRepositoryPort {
  _TransactionStubBeaconRepo(this.lockedBeacon);

  final BeaconEntity lockedBeacon;
  final statusTransitions = <_StatusTransitionCall>[];

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) =>
      fn(lockedBeacon);

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
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubCoordinationRepo implements CoordinationRepositoryPort {
  _StubCoordinationRepo(this._responseByUserId);

  final Map<String, int> _responseByUserId;

  @override
  Future<Map<String, int>> coordinationResponseTypeByOfferUserId(
    String beaconId,
  ) async =>
      _responseByUserId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubHelpOfferRepo implements HelpOfferRepositoryPort {
  _StubHelpOfferRepo(this._offers);

  final List<HelpOfferEntity> _offers;

  @override
  Future<List<HelpOfferEntity>> fetchByBeaconId(String beaconId) async =>
      _offers;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImageRepo extends Fake implements ImageRepositoryPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

void main() {
  const authorId = 'Uauth';
  const beaconId = 'Bopen';
  final now = DateTime.utc(2026, 6, 25);

  BeaconEntity openBeacon({String author = authorId}) => BeaconEntity(
        id: beaconId,
        title: 'Open beacon',
        author: UserEntity(id: author),
        createdAt: now,
        updatedAt: now,
        status: BeaconStatus.open,
      );

  HelpOfferEntity helpOffer({String userId = 'Uhelper'}) => HelpOfferEntity(
        beaconId: beaconId,
        userId: userId,
        createdAt: now,
        updatedAt: now,
      );

  BeaconCase buildCase({
    required BeaconEntity beacon,
    Map<String, int> coordinationResponses = const {},
    List<HelpOfferEntity> offers = const [],
  }) {
    return BeaconCase(
      _TransactionStubBeaconRepo(beacon),
      _FakeImageRepo(),
      _FakeTaskRepo(),
      _StubCoordinationRepo(coordinationResponses),
      _StubHelpOfferRepo(offers),
      FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconCaseCancelTest'),
    );
  }

  group('beaconCancel', () {
    test('author cancels open beacon with no committers', () async {
      final beacon = openBeacon();
      final beaconRepo = _TransactionStubBeaconRepo(beacon);
      final case_ = BeaconCase(
        beaconRepo,
        _FakeImageRepo(),
        _FakeTaskRepo(),
        _StubCoordinationRepo({}),
        _StubHelpOfferRepo([helpOffer()]),
        FakeBeaconAccessGuard(),
        env: Env(environment: Environment.test),
        logger: Logger('BeaconCaseCancelTest'),
      );

      final result = await case_.beaconCancel(
        beaconId: beaconId,
        userId: authorId,
      );

      expect(result.id, beaconId);
      expect(result.status, BeaconStatus.cancelled.smallintValue);
      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.open,
          toStatus: BeaconStatus.cancelled,
          reason: BeaconLifecycleChangeReason.cancelled,
          actorId: authorId,
        ),
      ]);
    });

    test('rejects when beacon is not in open family', () async {
      final beacon = openBeacon().copyWith(status: BeaconStatus.closed);
      final case_ = buildCase(beacon: beacon);

      await expectLater(
        case_.beaconCancel(beaconId: beaconId, userId: authorId),
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
    });

    test('rejects when caller is not the author', () async {
      final case_ = buildCase(beacon: openBeacon());

      await expectLater(
        case_.beaconCancel(beaconId: beaconId, userId: 'Uother'),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.notEligible,
            ).codeNumber,
          ),
        ),
      );
    });

    test('rejects when an acknowledged committer exists', () async {
      const helperId = 'Uhelper';
      final case_ = buildCase(
        beacon: openBeacon(),
        offers: [helpOffer(userId: helperId)],
        coordinationResponses: {
          helperId: CoordinationResponseType.useful.smallintValue,
        },
      );

      await expectLater(
        case_.beaconCancel(beaconId: beaconId, userId: authorId),
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
    });
  });
}
