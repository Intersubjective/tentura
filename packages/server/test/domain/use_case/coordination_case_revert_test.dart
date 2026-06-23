import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/coordination/beacon_coordination_status.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/env.dart';

import 'help_offer_case_mocks.mocks.dart';

class _TrackingEvaluationRepository implements EvaluationRepositoryPort {
  BeaconReviewWindowRecord? reviewWindowResult;
  int downgradeSubmittedCalls = 0;
  int deleteScaffoldingCalls = 0;

  @override
  Future<void> downgradeSubmittedReviewsToDraft(String beaconId) async {
    downgradeSubmittedCalls++;
  }

  @override
  Future<void> deleteReviewScaffoldingForBeacon(String beaconId) async {
    deleteScaffoldingCalls++;
    reviewWindowResult = null;
  }

  @override
  Future<BeaconReviewWindowRecord?> getReviewWindow(String beaconId) async =>
      reviewWindowResult;

  @override
  Future<void> closeExpiredWindows() async {}

  @override
  Future<int> countDistinctEvaluatorsForEvaluated({
    required String beaconId,
    required String evaluatedUserId,
  }) async =>
      0;

  @override
  Future<BeaconEvaluationRecord?> getEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async =>
      null;

  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluator({
    required String beaconId,
    required String evaluatorId,
  }) async =>
      [];

  @override
  Future<int?> getReviewUserStatus(String beaconId, String userId) async =>
      null;

  @override
  Future<void> insertParticipant({
    required String beaconId,
    required String userId,
    required int role,
    required String contributionSummary,
    required String causalHint,
  }) async {}

  @override
  Future<void> insertReviewStatus({
    required String beaconId,
    required String userId,
    int status = 0,
  }) async {}

  @override
  Future<void> insertReviewWindow({
    required String beaconId,
    required DateTime openedAt,
    required DateTime closesAt,
  }) async {}

  @override
  Future<void> insertVisibility({
    required String beaconId,
    required String evaluatorId,
    required String participantId,
  }) async {}

  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluatedUser({
    required String beaconId,
    required String evaluatedUserId,
  }) async =>
      [];

  @override
  Future<List<BeaconEvaluationParticipantRecord>> listParticipants(
    String beaconId,
  ) async =>
      [];

  @override
  Future<List<BeaconEvaluationVisibilityRecord>> listVisibilityForEvaluator(
    String beaconId,
    String evaluatorId,
  ) async =>
      [];

  @override
  Future<List<BeaconEvaluationVisibilityRecord>> listAllVisibility(
    String beaconId,
  ) async =>
      [];

  @override
  Future<List<BeaconEvaluationRecord>> listDraftRowsForBeacon(
    String beaconId,
  ) async =>
      [];

  @override
  Future<void> deleteEvaluationRow({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async {}

  @override
  Future<void> finalizeSubmittedEvaluationsForBeacon(String beaconId) async {}

  @override
  Future<void> deleteDraftEvaluationsForBeacon(String beaconId) async {}

  @override
  Future<Map<String, int>> listReviewStatusesForBeacon(String beaconId) async =>
      {};

  @override
  Future<DateTime> extendReviewWindow(String beaconId) async =>
      DateTime.timestamp().add(const Duration(days: 7));

  @override
  Future<void> closeBeaconReviewWindow(
    String beaconId, {
    required String reason,
    String? actorUserId,
  }) async {}

  @override
  Future<void> setReviewUserStatus({
    required String beaconId,
    required String userId,
    required int status,
  }) async {}

  @override
  Future<void> upsertEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
    required String reasonTagsCsv,
    required String note,
    int status = BeaconEvaluationRowStatus.submitted,
  }) async {}
}

class _LifecycleTransitionCall {
  const _LifecycleTransitionCall({
    required this.beaconId,
    required this.fromState,
    required this.toState,
    required this.reason,
    this.actorId,
  });

  final String beaconId;
  final int fromState;
  final int toState;
  final String reason;
  final String? actorId;

  @override
  bool operator ==(Object other) =>
      other is _LifecycleTransitionCall &&
      other.beaconId == beaconId &&
      other.fromState == fromState &&
      other.toState == toState &&
      other.reason == reason &&
      other.actorId == actorId;

  @override
  int get hashCode => Object.hash(beaconId, fromState, toState, reason, actorId);
}

class _TransactionBeaconRepo implements BeaconRepositoryPort {
  _TransactionBeaconRepo(this.locked);

  BeaconEntity locked;
  final lifecycleTransitions = <_LifecycleTransitionCall>[];

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
  Future<void> recordBeaconLifecycleTransition({
    required String beaconId,
    required int fromState,
    required int toState,
    required String reason,
    String? actorId,
  }) async {
    lifecycleTransitions.add(
      _LifecycleTransitionCall(
        beaconId: beaconId,
        fromState: fromState,
        toState: toState,
        reason: reason,
        actorId: actorId,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const beaconId = 'B1';
  const authorId = 'Uauth';
  const stewardId = 'Usteward';
  const outsiderId = 'Uother';
  const offerUserId = 'Uhelper';

  final now = DateTime.utc(2025);

  BeaconEntity beacon({required int state}) => BeaconEntity(
        id: beaconId,
        title: 't',
        author: UserEntity(id: authorId),
        createdAt: now,
        updatedAt: now,
        state: state,
      );

  BeaconReviewWindowRecord openWindow() {
    final opened = now.subtract(const Duration(hours: 1));
    return BeaconReviewWindowRecord(
      beaconId: beaconId,
      openedAt: opened,
      closesAt: opened.add(const Duration(days: 7)),
      status: 0,
      extensionsUsed: 0,
      createdAt: opened,
      updatedAt: now,
    );
  }

  late _TransactionBeaconRepo beaconRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockCoordinationRepositoryPort coordinationRepo;
  late MockBeaconRoomCoordinationPort roomRepo;
  late _TrackingEvaluationRepository evalRepo;
  late CoordinationCase case_;

  setUp(() {
    beaconRepo = _TransactionBeaconRepo(beacon(state: 0));
    helpOfferRepo = MockHelpOfferRepositoryPort();
    coordinationRepo = MockCoordinationRepositoryPort();
    roomRepo = MockBeaconRoomCoordinationPort();
    evalRepo = _TrackingEvaluationRepository();
    case_ = CoordinationCase(
      beaconRepo,
      helpOfferRepo,
      coordinationRepo,
      roomRepo,
      evalRepo,
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationCaseRevertTest'),
    );
  });

  void stubTransaction(BeaconEntity locked) {
    beaconRepo.locked = locked;
    when(
      coordinationRepo.setBeaconCoordinationFields(
        beaconId: anyNamed('beaconId'),
        coordinationStatus: anyNamed('coordinationStatus'),
      ),
    ).thenAnswer((_) async {});
  }

  group('setBeaconCoordinationStatus more help', () {
    test('on wrapping up reverts lifecycle and preserves review content', () async {
      evalRepo.reviewWindowResult = openWindow();
      stubTransaction(beacon(state: 5));

      final ok = await case_.setBeaconCoordinationStatus(
        beaconId: beaconId,
        authorUserId: authorId,
        status: BeaconCoordinationStatus.moreOrDifferentHelpNeeded.smallintValue,
      );

      expect(ok, isTrue);
      expect(evalRepo.downgradeSubmittedCalls, 1);
      expect(evalRepo.deleteScaffoldingCalls, 1);
      expect(beaconRepo.lifecycleTransitions, [
        _LifecycleTransitionCall(
          beaconId: beaconId,
          fromState: 5,
          toState: 0,
          reason: BeaconLifecycleChangeReason.reopenedFromReview,
          actorId: authorId,
        ),
      ]);
      verify(
        coordinationRepo.setBeaconCoordinationFields(
          beaconId: beaconId,
          coordinationStatus:
              BeaconCoordinationStatus.moreOrDifferentHelpNeeded.smallintValue,
        ),
      ).called(1);
    });

    test('on open only sets coordination label', () async {
      stubTransaction(beacon(state: 0));

      await case_.setBeaconCoordinationStatus(
        beaconId: beaconId,
        authorUserId: authorId,
        status: BeaconCoordinationStatus.moreOrDifferentHelpNeeded.smallintValue,
      );

      expect(evalRepo.downgradeSubmittedCalls, 0);
      expect(evalRepo.deleteScaffoldingCalls, 0);
      expect(beaconRepo.lifecycleTransitions, isEmpty);
    });

    test('steward may trigger revert on wrapping up', () async {
      evalRepo.reviewWindowResult = openWindow();
      stubTransaction(beacon(state: 5));
      when(
        roomRepo.isBeaconSteward(
          beaconId: beaconId,
          userId: stewardId,
        ),
      ).thenAnswer((_) async => true);

      await case_.setBeaconCoordinationStatus(
        beaconId: beaconId,
        authorUserId: stewardId,
        status: BeaconCoordinationStatus.moreOrDifferentHelpNeeded.smallintValue,
      );

      expect(evalRepo.downgradeSubmittedCalls, 1);
      expect(beaconRepo.lifecycleTransitions, [
        _LifecycleTransitionCall(
          beaconId: beaconId,
          fromState: 5,
          toState: 0,
          reason: BeaconLifecycleChangeReason.reopenedFromReview,
          actorId: stewardId,
        ),
      ]);
    });

    test('rejects outsider on wrapping up revert', () async {
      stubTransaction(beacon(state: 5));
      when(
        roomRepo.isBeaconSteward(
          beaconId: beaconId,
          userId: outsiderId,
        ),
      ).thenAnswer((_) async => false);

      await expectLater(
        case_.setBeaconCoordinationStatus(
          beaconId: beaconId,
          authorUserId: outsiderId,
          status:
              BeaconCoordinationStatus.moreOrDifferentHelpNeeded.smallintValue,
        ),
        throwsA(isA<HelpOfferCoordinationException>()),
      );
    });

    test('throws when review window is not open on wrapping up revert', () async {
      evalRepo.reviewWindowResult = null;
      stubTransaction(beacon(state: 5));

      await expectLater(
        case_.setBeaconCoordinationStatus(
          beaconId: beaconId,
          authorUserId: authorId,
          status:
              BeaconCoordinationStatus.moreOrDifferentHelpNeeded.smallintValue,
        ),
        throwsA(
          isA<EvaluationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const EvaluationExceptionCodes(
              EvaluationExceptionCode.reviewWindowNotOpen,
            ).codeNumber,
          ),
        ),
      );
    });
  });

  group('setCoordinationResponse', () {
    HelpOfferEntity activeOffer() => HelpOfferEntity(
          beaconId: beaconId,
          userId: offerUserId,
          createdAt: now,
          updatedAt: now,
        );

    void stubOpenCoordinationMutation() {
      when(
        helpOfferRepo.fetchByBeaconId(beaconId),
      ).thenAnswer((_) async => [activeOffer()]);
      when(
        coordinationRepo.upsertResponse(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          authorUserId: anyNamed('authorUserId'),
          responseType: anyNamed('responseType'),
        ),
      ).thenAnswer((_) async {});
      when(
        coordinationRepo.beaconCoordinationSnapshot(beaconId),
      ).thenAnswer(
        (_) async => (
          coordinationStatus:
              BeaconCoordinationStatus.enoughHelpOffered.smallintValue,
          coordinationStatusUpdatedAt: now,
        ),
      );
    }

    test('rejects wrapping up beacon', () async {
      beaconRepo.locked = beacon(state: 5);

      await expectLater(
        case_.setCoordinationResponse(
          beaconId: beaconId,
          offerUserId: offerUserId,
          authorUserId: authorId,
          responseType: CoordinationResponseType.useful.smallintValue,
          inviteToRoom: false,
          removeFromRoom: false,
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const HelpOfferCoordinationExceptionCodes(
              HelpOfferCoordinationExceptionCode.beaconNotOpen,
            ).codeNumber,
          ),
        ),
      );
      verifyNever(
        coordinationRepo.upsertResponse(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          authorUserId: anyNamed('authorUserId'),
          responseType: anyNamed('responseType'),
        ),
      );
    });

    test('rejects closed beacon', () async {
      beaconRepo.locked = beacon(state: 6);

      await expectLater(
        case_.setCoordinationResponse(
          beaconId: beaconId,
          offerUserId: offerUserId,
          authorUserId: authorId,
          responseType: CoordinationResponseType.useful.smallintValue,
          inviteToRoom: false,
          removeFromRoom: false,
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const HelpOfferCoordinationExceptionCodes(
              HelpOfferCoordinationExceptionCode.beaconNotOpen,
            ).codeNumber,
          ),
        ),
      );
      verifyNever(
        coordinationRepo.upsertResponse(
          beaconId: anyNamed('beaconId'),
          offerUserId: anyNamed('offerUserId'),
          authorUserId: anyNamed('authorUserId'),
          responseType: anyNamed('responseType'),
        ),
      );
    });

    test('succeeds on open beacon', () async {
      beaconRepo.locked = beacon(state: 0);
      stubOpenCoordinationMutation();

      final result = await case_.setCoordinationResponse(
        beaconId: beaconId,
        offerUserId: offerUserId,
        authorUserId: authorId,
        responseType: CoordinationResponseType.useful.smallintValue,
        inviteToRoom: false,
        removeFromRoom: false,
      );

      expect(
        result.coordinationStatus,
        BeaconCoordinationStatus.enoughHelpOffered.smallintValue,
      );
      verify(
        coordinationRepo.upsertResponse(
          beaconId: beaconId,
          offerUserId: offerUserId,
          authorUserId: authorId,
          responseType: CoordinationResponseType.useful.smallintValue,
        ),
      ).called(1);
    });
  });
}
