import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/entity/review_close_snapshot.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/test_attention_harness.dart';
import 'help_offer_case_mocks.mocks.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

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
  }) async => 0;

  @override
  Future<BeaconEvaluationRecord?> getEvaluation({
    required String beaconId,
    required String evaluatorId,
    required String evaluatedUserId,
  }) async => null;

  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluator({
    required String beaconId,
    required String evaluatorId,
  }) async => [];

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
  }) async => [];

  @override
  Future<List<BeaconEvaluationParticipantRecord>> listParticipants(
    String beaconId,
  ) async => [];

  @override
  Future<List<BeaconEvaluationVisibilityRecord>> listVisibilityForEvaluator(
    String beaconId,
    String evaluatorId,
  ) async => [];

  @override
  Future<List<BeaconEvaluationVisibilityRecord>> listAllVisibility(
    String beaconId,
  ) async => [];

  @override
  Future<List<BeaconEvaluationRecord>> listDraftRowsForBeacon(
    String beaconId,
  ) async => [];

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
  Future<ReviewCloseSnapshot?> closeReviewWindow(
    String beaconId, {
    required String reason,
    String? actorUserId,
  }) async =>
      null;

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

class _TransactionBeaconRepo implements BeaconRepositoryPort {
  _TransactionBeaconRepo(this.locked);

  BeaconEntity locked;
  final statusTransitions = <_StatusTransitionCall>[];

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async => locked;

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) => fn(locked);

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

void main() {
  const beaconId = 'B1';
  const authorId = 'Uauth';
  const stewardId = 'Usteward';
  const outsiderId = 'Uother';
  const offerUserId = 'Uhelper';

  final now = DateTime.utc(2025);

  BeaconEntity beacon({required BeaconStatus status}) => BeaconEntity(
    id: beaconId,
    title: 't',
    author: UserEntity(id: authorId),
    createdAt: now,
    updatedAt: now,
    status: status,
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
  late MockBeaconRoomRepositoryPort roomRepo;
  late MockBeaconRoomNotificationPort roomPush;
  late _TrackingEvaluationRepository evalRepo;
  late CoordinationCase case_;

  setUp(() {
    beaconRepo = _TransactionBeaconRepo(beacon(status: BeaconStatus.open));
    helpOfferRepo = MockHelpOfferRepositoryPort();
    coordinationRepo = MockCoordinationRepositoryPort();
    roomRepo = MockBeaconRoomRepositoryPort();
    roomPush = MockBeaconRoomNotificationPort();
    evalRepo = _TrackingEvaluationRepository();
    final attention = TestAttentionHarness();
    case_ = CoordinationCase(
      beaconRepo,
      helpOfferRepo,
      coordinationRepo,
      roomRepo,
      evalRepo,
      roomPush: roomPush,
      attentionIntents: attention.intents,
      attention: attention.transactional,
      guard: FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationCaseRevertTest'),
    );
  });

  void stubTransaction(BeaconEntity locked) {
    beaconRepo.locked = locked;
    when(
      coordinationRepo.beaconStatusSnapshot(beaconId),
    ).thenAnswer(
      (_) async => (
        status: beaconRepo.locked.status,
        statusChangedAt: now,
      ),
    );
  }

  CoordinationCase enabledCase(TestAttentionHarness attention) =>
      CoordinationCase(
        beaconRepo,
        helpOfferRepo,
        coordinationRepo,
        roomRepo,
        evalRepo,
        roomPush: roomPush,
        attentionIntents: attention.intents,
        attention: attention.transactional,
        guard: FakeBeaconAccessGuard(),
        env: Env(
          environment: Environment.test,
        ),
        logger: Logger('CoordinationCaseRevertTest'),
      );

  group('requestStatusChanged producer', () {
    test(
      'snapshots active and watcher audiences with recipient policy',
      () async {
        final attention = TestAttentionHarness(
          context: const BeaconNotificationContext(
            beaconAuthorId: authorId,
            admittedUserIds: {offerUserId},
            inboxStanceUserIds: {'Uwatcher'},
          ),
        );
        case_ = enabledCase(attention);
        stubTransaction(beacon(status: BeaconStatus.open));

        await case_.setBeaconStatus(
          beaconId: beaconId,
          authorUserId: authorId,
          status: BeaconStatus.enoughHelp.smallintValue,
        );

        final intent = attention.recorded.single;
        expect(intent.eventType, AttentionEventType.requestStatusChanged);
        expect(intent.sourceEventKey, startsWith('request_status:A'));
        final helper = intent.recipients.singleWhere(
          (recipient) => recipient.recipientId == offerUserId,
        );
        expect(helper.channelEligible, isTrue);
        final watcher = intent.recipients.singleWhere(
          (recipient) => recipient.recipientId == 'Uwatcher',
        );
        expect(watcher.channelEligible, isFalse);
        expect(watcher.collapseKey, startsWith('v1|request_status|'));
      },
    );

    test(
      'noop emits nothing and repeat after reversal has new identities',
      () async {
        final attention = TestAttentionHarness(
          context: const BeaconNotificationContext(
            beaconAuthorId: authorId,
            admittedUserIds: {offerUserId},
          ),
        );
        case_ = enabledCase(attention);
        stubTransaction(beacon(status: BeaconStatus.open));

        for (final status in [
          BeaconStatus.enoughHelp,
          BeaconStatus.enoughHelp,
          BeaconStatus.open,
          BeaconStatus.enoughHelp,
        ]) {
          await case_.setBeaconStatus(
            beaconId: beaconId,
            authorUserId: authorId,
            status: status.smallintValue,
          );
        }

        expect(attention.recorded, hasLength(3));
        expect(
          attention.recorded.map((intent) => intent.sourceEventKey).toSet(),
          hasLength(3),
        );
      },
    );
  });

  group('setBeaconStatus more help', () {
    test(
      'on wrapping up downgrades review and sets needsMoreHelp status',
      () async {
        evalRepo.reviewWindowResult = openWindow();
        stubTransaction(beacon(status: BeaconStatus.reviewOpen));

        final result = await case_.setBeaconStatus(
          beaconId: beaconId,
          authorUserId: authorId,
          status: BeaconStatus.needsMoreHelp.smallintValue,
        );

        expect(result.status, BeaconStatus.needsMoreHelp.smallintValue);
        expect(evalRepo.downgradeSubmittedCalls, 1);
        expect(evalRepo.deleteScaffoldingCalls, 1);
        expect(beaconRepo.statusTransitions, [
          _StatusTransitionCall(
            beaconId: beaconId,
            fromStatus: BeaconStatus.reviewOpen,
            toStatus: BeaconStatus.needsMoreHelp,
            reason: 'needsMoreHelp',
            actorId: authorId,
          ),
        ]);
      },
    );

    test('on open only sets needsMoreHelp status', () async {
      stubTransaction(beacon(status: BeaconStatus.open));

      await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: authorId,
        status: BeaconStatus.needsMoreHelp.smallintValue,
      );

      expect(evalRepo.downgradeSubmittedCalls, 0);
      expect(evalRepo.deleteScaffoldingCalls, 0);
      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.open,
          toStatus: BeaconStatus.needsMoreHelp,
          reason: 'needsMoreHelp',
          actorId: authorId,
        ),
      ]);
    });

    test('steward may trigger needsMoreHelp on wrapping up', () async {
      evalRepo.reviewWindowResult = openWindow();
      stubTransaction(beacon(status: BeaconStatus.reviewOpen));
      when(
        roomRepo.isBeaconSteward(
          beaconId: beaconId,
          userId: stewardId,
        ),
      ).thenAnswer((_) async => true);

      await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: stewardId,
        status: BeaconStatus.needsMoreHelp.smallintValue,
      );

      expect(evalRepo.downgradeSubmittedCalls, 1);
      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.reviewOpen,
          toStatus: BeaconStatus.needsMoreHelp,
          reason: 'needsMoreHelp',
          actorId: stewardId,
        ),
      ]);
    });

    test('rejects outsider on wrapping up revert', () async {
      stubTransaction(beacon(status: BeaconStatus.reviewOpen));
      when(
        roomRepo.isBeaconSteward(
          beaconId: beaconId,
          userId: outsiderId,
        ),
      ).thenAnswer((_) async => false);

      await expectLater(
        case_.setBeaconStatus(
          beaconId: beaconId,
          authorUserId: outsiderId,
          status: BeaconStatus.needsMoreHelp.smallintValue,
        ),
        throwsA(isA<HelpOfferCoordinationException>()),
      );
    });

    test(
      'throws when review window is not open on wrapping up revert',
      () async {
        evalRepo.reviewWindowResult = null;
        stubTransaction(beacon(status: BeaconStatus.reviewOpen));

        await expectLater(
          case_.setBeaconStatus(
            beaconId: beaconId,
            authorUserId: authorId,
            status: BeaconStatus.needsMoreHelp.smallintValue,
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
      },
    );
  });

  group('setBeaconStatus enough help', () {
    test('from open sets enoughHelp status', () async {
      stubTransaction(beacon(status: BeaconStatus.open));

      final result = await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: authorId,
        status: BeaconStatus.enoughHelp.smallintValue,
      );

      expect(result.status, BeaconStatus.enoughHelp.smallintValue);
      expect(evalRepo.downgradeSubmittedCalls, 0);
      expect(evalRepo.deleteScaffoldingCalls, 0);
      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.open,
          toStatus: BeaconStatus.enoughHelp,
          reason: 'enoughHelp',
          actorId: authorId,
        ),
      ]);
    });

    test('from needsMoreHelp sets enoughHelp status', () async {
      stubTransaction(beacon(status: BeaconStatus.needsMoreHelp));

      await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: authorId,
        status: BeaconStatus.enoughHelp.smallintValue,
      );

      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.needsMoreHelp,
          toStatus: BeaconStatus.enoughHelp,
          reason: 'enoughHelp',
          actorId: authorId,
        ),
      ]);
    });

    test('from reviewOpen sets enoughHelp status', () async {
      stubTransaction(beacon(status: BeaconStatus.reviewOpen));

      await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: authorId,
        status: BeaconStatus.enoughHelp.smallintValue,
      );

      expect(evalRepo.downgradeSubmittedCalls, 0);
      expect(evalRepo.deleteScaffoldingCalls, 0);
      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.reviewOpen,
          toStatus: BeaconStatus.enoughHelp,
          reason: 'enoughHelp',
          actorId: authorId,
        ),
      ]);
    });

    test('noop when already enoughHelp', () async {
      stubTransaction(beacon(status: BeaconStatus.enoughHelp));

      final result = await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: authorId,
        status: BeaconStatus.enoughHelp.smallintValue,
      );

      expect(result.status, BeaconStatus.enoughHelp.smallintValue);
      expect(beaconRepo.statusTransitions, isEmpty);
    });

    test('steward may set enoughHelp', () async {
      stubTransaction(beacon(status: BeaconStatus.open));
      when(
        roomRepo.isBeaconSteward(
          beaconId: beaconId,
          userId: stewardId,
        ),
      ).thenAnswer((_) async => true);

      await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: stewardId,
        status: BeaconStatus.enoughHelp.smallintValue,
      );

      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.open,
          toStatus: BeaconStatus.enoughHelp,
          reason: 'enoughHelp',
          actorId: stewardId,
        ),
      ]);
    });

    test('rejects outsider', () async {
      stubTransaction(beacon(status: BeaconStatus.open));
      when(
        roomRepo.isBeaconSteward(
          beaconId: beaconId,
          userId: outsiderId,
        ),
      ).thenAnswer((_) async => false);

      await expectLater(
        case_.setBeaconStatus(
          beaconId: beaconId,
          authorUserId: outsiderId,
          status: BeaconStatus.enoughHelp.smallintValue,
        ),
        throwsA(isA<HelpOfferCoordinationException>()),
      );
    });

    test('rejects disallowed transition from closed', () async {
      stubTransaction(beacon(status: BeaconStatus.closed));

      await expectLater(
        case_.setBeaconStatus(
          beaconId: beaconId,
          authorUserId: authorId,
          status: BeaconStatus.enoughHelp.smallintValue,
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const HelpOfferCoordinationExceptionCodes(
              HelpOfferCoordinationExceptionCode.invalidCoordinationStatus,
            ).codeNumber,
          ),
        ),
      );
    });
  });

  group('setBeaconStatus neutral open', () {
    test('from needsMoreHelp sets open status', () async {
      stubTransaction(beacon(status: BeaconStatus.needsMoreHelp));

      final result = await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: authorId,
        status: BeaconStatus.open.smallintValue,
      );

      expect(result.status, BeaconStatus.open.smallintValue);
      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.needsMoreHelp,
          toStatus: BeaconStatus.open,
          reason: 'neutralOpen',
          actorId: authorId,
        ),
      ]);
    });

    test('from enoughHelp sets open status', () async {
      stubTransaction(beacon(status: BeaconStatus.enoughHelp));

      await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: authorId,
        status: BeaconStatus.open.smallintValue,
      );

      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.enoughHelp,
          toStatus: BeaconStatus.open,
          reason: 'neutralOpen',
          actorId: authorId,
        ),
      ]);
    });

    test('from reviewOpen reopens to open', () async {
      stubTransaction(beacon(status: BeaconStatus.reviewOpen));

      await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: authorId,
        status: BeaconStatus.open.smallintValue,
      );

      expect(evalRepo.downgradeSubmittedCalls, 0);
      expect(evalRepo.deleteScaffoldingCalls, 0);
      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.reviewOpen,
          toStatus: BeaconStatus.open,
          reason: 'neutralOpen',
          actorId: authorId,
        ),
      ]);
    });

    test('noop when already open', () async {
      stubTransaction(beacon(status: BeaconStatus.open));

      final result = await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: authorId,
        status: BeaconStatus.open.smallintValue,
      );

      expect(result.status, BeaconStatus.open.smallintValue);
      expect(beaconRepo.statusTransitions, isEmpty);
    });

    test('steward may set neutral open', () async {
      stubTransaction(beacon(status: BeaconStatus.enoughHelp));
      when(
        roomRepo.isBeaconSteward(
          beaconId: beaconId,
          userId: stewardId,
        ),
      ).thenAnswer((_) async => true);

      await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: stewardId,
        status: BeaconStatus.open.smallintValue,
      );

      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.enoughHelp,
          toStatus: BeaconStatus.open,
          reason: 'neutralOpen',
          actorId: stewardId,
        ),
      ]);
    });

    test('rejects outsider', () async {
      stubTransaction(beacon(status: BeaconStatus.enoughHelp));
      when(
        roomRepo.isBeaconSteward(
          beaconId: beaconId,
          userId: outsiderId,
        ),
      ).thenAnswer((_) async => false);

      await expectLater(
        case_.setBeaconStatus(
          beaconId: beaconId,
          authorUserId: outsiderId,
          status: BeaconStatus.open.smallintValue,
        ),
        throwsA(isA<HelpOfferCoordinationException>()),
      );
    });

    test('rejects disallowed transition from closed', () async {
      stubTransaction(beacon(status: BeaconStatus.closed));

      await expectLater(
        case_.setBeaconStatus(
          beaconId: beaconId,
          authorUserId: authorId,
          status: BeaconStatus.open.smallintValue,
        ),
        throwsA(
          isA<HelpOfferCoordinationException>().having(
            (e) => e.code.codeNumber,
            'codeNumber',
            const HelpOfferCoordinationExceptionCodes(
              HelpOfferCoordinationExceptionCode.invalidCoordinationStatus,
            ).codeNumber,
          ),
        ),
      );
    });
  });

  group('setBeaconStatus cannot reach review or close', () {
    test(
      'reviewOpen smallint maps to neutral open not review window',
      () async {
        stubTransaction(beacon(status: BeaconStatus.needsMoreHelp));

        await case_.setBeaconStatus(
          beaconId: beaconId,
          authorUserId: authorId,
          status: BeaconStatus.reviewOpen.smallintValue,
        );

        expect(beaconRepo.statusTransitions, [
          _StatusTransitionCall(
            beaconId: beaconId,
            fromStatus: BeaconStatus.needsMoreHelp,
            toStatus: BeaconStatus.open,
            reason: 'neutralOpen',
            actorId: authorId,
          ),
        ]);
        expect(beaconRepo.locked.status, BeaconStatus.open);
      },
    );

    test('closed smallint maps to neutral open not closed', () async {
      stubTransaction(beacon(status: BeaconStatus.enoughHelp));

      await case_.setBeaconStatus(
        beaconId: beaconId,
        authorUserId: authorId,
        status: BeaconStatus.closed.smallintValue,
      );

      expect(beaconRepo.statusTransitions, [
        _StatusTransitionCall(
          beaconId: beaconId,
          fromStatus: BeaconStatus.enoughHelp,
          toStatus: BeaconStatus.open,
          reason: 'neutralOpen',
          actorId: authorId,
        ),
      ]);
      expect(beaconRepo.locked.status, BeaconStatus.open);
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
        coordinationRepo.beaconStatusSnapshot(beaconId),
      ).thenAnswer(
        (_) async => (
          status: BeaconStatus.enoughHelp,
          statusChangedAt: now,
        ),
      );
    }

    test('rejects wrapping up beacon', () async {
      beaconRepo.locked = beacon(status: BeaconStatus.reviewOpen);

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
      beaconRepo.locked = beacon(status: BeaconStatus.closed);

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
      beaconRepo.locked = beacon(status: BeaconStatus.open);
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
        result.status,
        BeaconStatus.enoughHelp.smallintValue,
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
