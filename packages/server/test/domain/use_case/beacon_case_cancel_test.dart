import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
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
  }) => fn(lockedBeacon);

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

class _StubHelpOfferRepo implements HelpOfferRepositoryPort {
  _StubHelpOfferRepo(this._offers);

  final List<HelpOfferEntity> _offers;

  @override
  Future<List<HelpOfferEntity>> fetchByBeaconId(String beaconId) async =>
      _offers;

  @override
  Future<List<HelpOfferEntity>> fetchAllByBeaconId(String beaconId) async =>
      _offers;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImageRepo extends Fake implements ImageRepositoryPort {}

class _FakeImageObjectGc extends Fake implements ImageObjectGcPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

void main() {
  const authorId = 'Uauth';
  const beaconId = 'Bopen';
  const helperId = 'Uhelper';
  final now = DateTime.utc(2026, 6, 25);

  BeaconEntity openBeacon({String author = authorId}) => BeaconEntity(
    id: beaconId,
    title: 'Open beacon',
    author: UserEntity(id: author),
    createdAt: now,
    updatedAt: now,
    status: BeaconStatus.open,
  );

  HelpOfferEntity helpOffer({String userId = helperId}) => HelpOfferEntity(
    beaconId: beaconId,
    userId: userId,
    createdAt: now,
    updatedAt: now,
  );

  CommitmentQueryCase commitmentQueryCaseFromEvents(
    List<CommitmentEvent> events,
  ) {
    final commitmentRepo = RecordingCommitmentRepository(
      eventsByPair: {
        commitmentPairKey(beaconId, helperId): events,
      },
    );
    return CommitmentQueryCase(
      commitmentRepo,
      _StubHelpOfferRepo(const []),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconCaseCancelTest'),
    );
  }

  BeaconCase buildCase({
    required BeaconEntity beacon,
    List<HelpOfferEntity> offers = const [],
    CommitmentQueryCase? commitmentQueryCase,
  }) {
    final attention = TestAttentionHarness();
    return BeaconCase(
      _TransactionStubBeaconRepo(beacon),
      _FakeImageRepo(),
      _FakeImageObjectGc(),
      _FakeTaskRepo(),
      commitmentQueryCase ?? noopCommitmentQueryCase(),
      FakeBeaconAccessGuard(),
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconCaseCancelTest'),
    );
  }

  group('beaconCancel', () {
    test('author cancels open beacon with no committers', () async {
      final beacon = openBeacon();
      final beaconRepo = _TransactionStubBeaconRepo(beacon);
      final attention = TestAttentionHarness();
      final case_ = BeaconCase(
        beaconRepo,
        _FakeImageRepo(),
        _FakeImageObjectGc(),
        _FakeTaskRepo(),
        noopCommitmentQueryCase(),
        FakeBeaconAccessGuard(),
        attentionIntents: attention.intents,
        attention: attention.transactional,
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

    test(
      'snapshots cancellation audience before the destructive transition',
      () async {
        final beacon = openBeacon();
        final beaconRepo = _TransactionStubBeaconRepo(beacon);
        final attention = TestAttentionHarness(
          context: const BeaconNotificationContext(
            beaconAuthorId: authorId,
            admittedUserIds: {'Uhelper'},
          ),
          onContextLoaded: () => expect(beaconRepo.statusTransitions, isEmpty),
        );
        final case_ = BeaconCase(
          beaconRepo,
          _FakeImageRepo(),
          _FakeImageObjectGc(),
          _FakeTaskRepo(),
          noopCommitmentQueryCase(),
          FakeBeaconAccessGuard(),
          attentionIntents: attention.intents,
          attention: attention.transactional,
          env: Env(
            environment: Environment.test,
          ),
          logger: Logger('BeaconCaseCancelTest'),
        );

        await case_.beaconCancel(beaconId: beaconId, userId: authorId);

        final intent = attention.recorded.single;
        expect(intent.eventType, AttentionEventType.requestStatusChanged);
        expect(intent.recipients.single.recipientId, 'Uhelper');
      },
    );

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

    test('rejects when a committer was ever acknowledged', () async {
      final case_ = buildCase(
        beacon: openBeacon(),
        offers: [helpOffer()],
        commitmentQueryCase: commitmentQueryCaseFromEvents([
          CommitmentEvent(
            id: 'CE-1',
            seq: 1,
            beaconId: beaconId,
            userId: helperId,
            actorUserId: authorId,
            kind: CommitmentEventKind.acknowledged,
            reason: null,
            createdAt: now,
          ),
        ]),
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

    test(
      'rejects after accept then withdraw when commitment history remains',
      () async {
        final case_ = buildCase(
          beacon: openBeacon(),
          offers: const [],
          commitmentQueryCase: commitmentQueryCaseFromEvents([
            CommitmentEvent(
              id: 'CE-1',
              seq: 1,
              beaconId: beaconId,
              userId: helperId,
              actorUserId: authorId,
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
          case_.beaconCancel(beaconId: beaconId, userId: authorId),
          throwsA(
            isA<EvaluationException>().having(
              (e) => e.description,
              'description',
              'Cannot cancel a request that ever had a committer',
            ),
          ),
        );
      },
    );
  });
}
