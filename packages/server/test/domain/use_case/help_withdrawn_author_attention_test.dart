import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura_server/consts/beacon_plan_consts.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/beacon_plan.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/domain/port/beacon_plan_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/plan_attention_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_plan_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/plan_attention_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';
import 'help_offer_case_mocks.mocks.dart';

// #516 residual (option A, Vadim 2026-10-22): when a helper withdraws, the
// author's attention item says who withdrew and why. The `promiseWithdrawn`
// receipt from `AttentionIntentCase.helpWithdrawn` already reaches the author,
// but it carries neither the withdraw reason nor the helper's note, so the
// author's Request card can only say «Items updated».
//
// Pinned shape: `helpWithdrawn(withdrawReason:, note:)`; the helper's note is
// the receipt excerpt, the reason key rides the presentation payload as
// `withdrawReason` (one of kAllowedWithdrawReasonKeys), and the author (not
// the withdrawing helper) is a recipient.
//
// Part (2), the next step: the Request's next step is the plan's first open
// step (the free-text `nextStep` field has no owner). A withdrawing helper's
// plan steps are freed by `BeaconPlanCase.unassignOnLeave`, whose revision
// tells the author `planStepUnassigned`. The regressions at the bottom pin
// both links of that chain.

const _author = 'Uauth';
const _helper = 'Unina';
const _beaconId = 'B1';
const _note = 'Sorry, Saturday morning fell through';

class _Beacons extends Fake implements BeaconRepositoryPort {
  final _beacon = BeaconEntity(
    id: _beaconId,
    title: 'Move a sofa',
    author: const UserEntity(id: _author),
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async => _beacon;

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) => fn(_beacon);
}

Set<String> _recipientIds(AttentionDispatchIntent intent) => {
  for (final r in intent.recipients) r.recipientId,
};

Map<String, Object?> _payloadFor(
  AttentionDispatchIntent intent,
  String recipientId,
) {
  final recipient = intent.recipients.singleWhere(
    (r) => r.recipientId == recipientId,
  );
  return const AttentionPolicy()
      .project(
        eventType: intent.eventType,
        recipientId: recipient.recipientId,
        recipientReasons: recipient.reasons,
        role: recipient.role,
      )
      .presentationPayload;
}

HelpOfferCase _withdrawCase(
  TestAttentionHarness harness, {
  BeaconPlanCase? beaconPlan,
}) {
  final helpOfferRepo = MockHelpOfferRepositoryPort();
  final roomRepo = MockBeaconRoomRepositoryPort();
  when(
    roomRepo.findParticipant(beaconId: _beaconId, userId: _helper),
  ).thenAnswer((_) async => null);
  when(helpOfferRepo.fetchAllByBeaconId(_beaconId)).thenAnswer(
    (_) async => [
      HelpOfferEntity(
        beaconId: _beaconId,
        userId: _helper,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ],
  );
  return HelpOfferCase(
    helpOfferRepo,
    _Beacons(),
    RecordingCommitmentRepository(),
    MockInboxRepositoryPort(),
    CapabilityCase(
      MockPersonCapabilityEventRepositoryPort(),
      env: Env(environment: Environment.test),
      logger: Logger('HelpWithdrawnAuthorAttentionTest'),
    ),
    FakeBeaconAccessGuard(),
    roomRepository: roomRepo,
    attentionIntents: harness.intents,
    attention: harness.transactional,
    beaconPlan: beaconPlan,
    env: Env(environment: Environment.test),
    logger: Logger('HelpWithdrawnAuthorAttentionTest'),
  );
}

/// Records `unassignOnLeave` calls (the plan cleanup a withdrawal runs).
final class _RecordingPlan extends Fake implements BeaconPlanCase {
  final calls = <({String beaconId, String userId, String? actorId})>[];

  @override
  Future<void> unassignOnLeave({
    required AttentionTransaction transaction,
    required String beaconId,
    required String userId,
    String? actorId,
  }) async {
    calls.add((beaconId: beaconId, userId: userId, actorId: actorId));
  }
}

/// The real plan effects with the obligation reconcile switched off (it reads
/// the plan store; not what these tests are about).
final class _PlanEffects extends PlanAttentionCase {
  _PlanEffects(TestAttentionHarness harness)
    : super(
        _NoPlanRepo(),
        _NoAdmission(),
        _NoPlanStore(),
        harness.intents,
        harness.transactional,
        _NoClosure(),
        _RoomContext(),
        env: Env(environment: Environment.test),
        logger: Logger('HelpWithdrawnAuthorAttentionTest'),
      );

  @override
  Future<void> reconcile({
    required String beaconId,
    AttentionTransaction? transaction,
    String? actorId,
    DateTime? now,
    bool pushNew = true,
  }) async {}
}

final class _NoPlanRepo extends Fake implements BeaconPlanRepositoryPort {}

final class _NoAdmission extends Fake implements BeaconHierarchyCommandPort {}

final class _NoPlanStore extends Fake implements PlanAttentionRepositoryPort {}

final class _NoClosure extends Fake implements ClosureRepositoryPort {}

final class _RoomContext extends Fake
    implements BeaconRoomNotificationContextPort {
  @override
  Future<BeaconNotificationContext> loadContextForBeacon(
    String beaconId,
  ) async => const BeaconNotificationContext(
    beaconAuthorId: _author,
    admittedUserIds: {'Uomar'},
  );
}

void main() {
  late TestAttentionHarness harness;

  setUp(() {
    harness = TestAttentionHarness(
      context: const BeaconNotificationContext(
        beaconAuthorId: _author,
        admittedUserIds: {'Uomar'},
      ),
    );
  });

  group('#516 helpWithdrawn tells the author who left and why', () {
    test('the author receipt carries the reason key and the note', () async {
      final intent = await harness.intents.helpWithdrawn(
        beaconId: _beaconId,
        withdrawerUserId: _helper,
        sourceEventKey: 'help_withdrawn:A1',
        withdrawReason: 'timing',
        note: _note,
      );

      expect(intent.eventType, AttentionEventType.promiseWithdrawn);
      expect(_recipientIds(intent), contains(_author));
      expect(_recipientIds(intent), isNot(contains(_helper)));
      final payload = _payloadFor(intent, _author);
      expect(payload['withdrawReason'], 'timing');
      expect(payload['excerpt'], _note);
      expect(payload['actorUserId'], _helper);
    });

    test('no note: the reason key still rides, the excerpt is empty', () async {
      final intent = await harness.intents.helpWithdrawn(
        beaconId: _beaconId,
        withdrawerUserId: _helper,
        sourceEventKey: 'help_withdrawn:A2',
        withdrawReason: 'cannot_do_it',
      );

      final payload = _payloadFor(intent, _author);
      expect(payload['withdrawReason'], 'cannot_do_it');
      expect(payload['excerpt'], '');
    });

    test('guard: an unknown reason key is never written', () async {
      final intent = await harness.intents.helpWithdrawn(
        beaconId: _beaconId,
        withdrawerUserId: _helper,
        sourceEventKey: 'help_withdrawn:A3',
        withdrawReason: 'drop table',
        note: _note,
      );

      final payload = _payloadFor(intent, _author);
      expect(payload.containsKey('withdrawReason'), isFalse);
      expect(payload['excerpt'], _note);
    });

    test('guard: a withdrawn promise carries no withdraw reason', () async {
      final intent = await harness.intents.promiseChanged(
        beaconId: _beaconId,
        actorUserId: _helper,
        excerpt: 'Cannot bring the van',
        targetPersonId: _author,
        coordinationItemId: 'item1',
        sourceEventKey: 'promise:A4',
        withdrawn: true,
      );

      expect(intent.eventType, AttentionEventType.promiseWithdrawn);
      final payload = _payloadFor(intent, _author);
      expect(payload.containsKey('withdrawReason'), isFalse);
    });
  });

  group('#516 HelpOfferCase.withdraw passes the reason and note on', () {
    test('the recorded author item has the reason and the note', () async {
      final case_ = _withdrawCase(harness);

      await case_.withdraw(
        beaconId: _beaconId,
        userId: _helper,
        withdrawReason: 'timing',
        message: _note,
      );

      final intent = harness.recorded.single;
      expect(intent.eventType, AttentionEventType.promiseWithdrawn);
      expect(_recipientIds(intent), contains(_author));
      expect(_recipientIds(intent), isNot(contains(_helper)));
      final payload = _payloadFor(intent, _author);
      expect(payload['withdrawReason'], 'timing');
      expect(payload['excerpt'], _note);
    });
  });

  group('#516 part 2 regression: a withdrawal frees the helper plan steps', () {
    test('withdraw runs unassignOnLeave for the helper as actor', () async {
      final plan = _RecordingPlan();
      final case_ = _withdrawCase(harness, beaconPlan: plan);

      await case_.withdraw(
        beaconId: _beaconId,
        userId: _helper,
        withdrawReason: 'timing',
        message: _note,
      );

      expect(plan.calls, [
        (beaconId: _beaconId, userId: _helper, actorId: _helper),
      ]);
    });

    test('the leave revision tells the author planStepUnassigned', () async {
      await harness.transactional.runAction(
        actorUserId: _helper,
        action: (transaction) => _PlanEffects(harness).afterRevision(
          transaction: transaction,
          request: const PlanRequestInfo(
            beaconId: _beaconId,
            kind: BeaconKind.request,
            status: BeaconStatus.open,
            authorId: _author,
            title: 'Move a sofa',
          ),
          actorId: _helper,
          revision: PlanRevisionRecord(
            beaconId: _beaconId,
            seq: 3,
            baseSeq: 2,
            kind: PlanRevisionKind.unassignedOnLeave,
            snapshot: PlanSnapshot.fromJson(null),
            changes: const [
              {'stepId': 'PS1', 'title': 'Bring the van'},
            ],
            comment: '',
            createdAt: DateTime.utc(2026),
            actorId: _helper,
          ),
        ),
      );

      final unassigned = harness.recorded.singleWhere(
        (i) => i.eventType == AttentionEventType.planStepUnassigned,
      );
      expect(_recipientIds(unassigned), {_author});
      final payload = _payloadFor(unassigned, _author);
      expect(payload['actorUserId'], _helper);
    });
  });
}
