import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_event.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';
import 'package:tentura_server/domain/use_case/beacon_hierarchy_delivery_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/test_attention_harness.dart';

/// The facts a notification renderer needs (new deadline, previous status,
/// related Request, excerpt, backup flag, plan-step offset) are stored in the
/// recipient's `presentation_payload`. Each test builds the intent the way the
/// producing use case does, projects it for one recipient exactly as the
/// dispatch repository does, and reads the stored payload.
void main() {
  const policy = AttentionPolicy();

  Map<String, Object?> payloadFor(
    AttentionDispatchIntent intent,
    String recipientId,
  ) {
    final recipient = intent.recipients.singleWhere(
      (r) => r.recipientId == recipientId,
    );
    return policy
        .project(
          eventType: intent.eventType,
          recipientId: recipientId,
          recipientReasons: recipient.reasons,
          role: recipient.role,
          actorDisplayName: intent.actorDisplayName,
          beaconKind: intent.beaconKind,
        )
        .presentationPayload;
  }

  group('deadline notices', () {
    test('a changed deadline stores the new deadline as a UTC ISO string', () async {
      final harness = TestAttentionHarness();

      final intent = await harness.intents.deadlineChanged(
        beaconId: 'B1',
        actorUserId: 'author',
        participantUserIds: {'member'},
        oldEndAt: DateTime.utc(2026, 11, 20),
        newEndAt: DateTime.utc(2026, 11, 21, 15),
        sourceEventKey: 'deadline:B1:1',
      );

      expect(
        payloadFor(intent, 'member')['newEndAt'],
        '2026-11-21T15:00:00.000Z',
      );
    });

    test('a removed deadline stores no new deadline', () async {
      final harness = TestAttentionHarness();

      final intent = await harness.intents.deadlineChanged(
        beaconId: 'B1',
        actorUserId: 'author',
        participantUserIds: {'member'},
        oldEndAt: DateTime.utc(2026, 11, 20),
        newEndAt: null,
        sourceEventKey: 'deadline:B1:2',
      );

      final payload = payloadFor(intent, 'member');
      expect(payload['eventType'], 'deadlineChanged');
      expect(payload['newEndAt'], isNull);
    });

    test('a deadline reminder stores the deadline for every participant', () async {
      final harness = TestAttentionHarness();

      final intent = await harness.intents.deadlineReminder(
        beaconId: 'B1',
        participantUserIds: {'p1', 'p2'},
        deadline: DateTime.utc(2026, 11, 17, 9),
        sourceEventKey: 'deadline_reminder:B1',
      );

      for (final id in ['p1', 'p2']) {
        expect(
          payloadFor(intent, id)['newEndAt'],
          '2026-11-17T09:00:00.000Z',
          reason: id,
        );
      }
    });
  });

  group('request status notice', () {
    test('stores the status the Request had before, next to the new one', () async {
      final harness = TestAttentionHarness(
        context: const BeaconNotificationContext(
          beaconAuthorId: 'author',
          admittedUserIds: {'member'},
        ),
      );

      final intent = await harness.intents.requestStatusChanged(
        beaconId: 'B1',
        fromStatus: BeaconStatus.open.name,
        toStatus: BeaconStatus.cancelled.name,
        sourceEventKey: 'status:B1:1',
        actorUserId: 'author',
      );

      final payload = payloadFor(intent, 'member');
      expect(payload['toStatus'], 'cancelled');
      expect(payload['fromStatus'], 'open');
    });
  });

  group('hierarchy notice', () {
    for (final direction in BeaconHierarchyDeliveryDirection.values) {
      test('a ${direction.name} notice names the other Request', () async {
        final outbox = _DeliveryOutbox(
          event: BeaconHierarchyEvent(
            eventId: 'HE1',
            sourceBeaconId: 'B-source',
            sourceSequence: 1,
            fromStatus: BeaconStatus.open,
            toStatus: BeaconStatus.closed,
            occurredAt: DateTime.utc(2026, 3),
            actorUserId: 'actor',
          ),
          targetBeaconId: 'B-target',
          direction: direction,
        );
        final harness = TestAttentionHarness(
          context: const BeaconNotificationContext(
            beaconAuthorId: 'author',
            admittedUserIds: {'member'},
          ),
        );

        await BeaconHierarchyDeliveryCase(
          outbox,
          harness.transactional,
          harness.intents,
          env: Env(environment: 'test', printEnv: false),
          logger: Logger('notification_fact_payload_producers_test'),
        ).runDue(workerId: 'worker-a', now: DateTime.utc(2026, 3, 2));

        expect(harness.recorded, hasLength(1));
        final payload = payloadFor(harness.recorded.single, 'author');
        expect(payload['beaconId'], 'B-target');
        expect(payload['relatedBeaconId'], 'B-source');
        expect(payload['direction'], direction.name);
      });
    }
  });

  group('room message excerpt', () {
    test('a readable recipient gets the General message words', () async {
      final harness = TestAttentionHarness();

      final intent = await harness.intents.roomMessagePosted(
        beaconId: 'B1',
        messageId: 'M1',
        actorUserId: 'a',
        recipientUserIds: {'member'},
        excerpt: 'See you at 6',
        sourceEventKey: 'room:M1',
      );

      expect(payloadFor(intent, 'member')['excerpt'], 'See you at 6');
    });

    test('a recipient who cannot read the Request gets no words', () async {
      final harness = TestAttentionHarness(canReadBeaconContent: false);

      final intent = await harness.intents.roomMessagePosted(
        beaconId: 'B1',
        messageId: 'M1',
        actorUserId: 'a',
        recipientUserIds: {'member'},
        excerpt: 'See you at 6',
        sourceEventKey: 'room:M1',
      );

      expect(payloadFor(intent, 'member')['excerpt'], '');
    });

    test('a Questions message never stores its words', () async {
      final harness = TestAttentionHarness();

      final intent = await harness.intents.roomMessagePosted(
        beaconId: 'B1',
        messageId: 'M2',
        actorUserId: 'a',
        recipientUserIds: {'member'},
        excerpt: 'Where do we meet?',
        sourceEventKey: 'room:M2',
        questionsScope: true,
      );

      expect(payloadFor(intent, 'member')['excerpt'], '');
    });
  });

  group('help offer notice', () {
    Future<Map<String, Object?>> authorPayload({
      required bool backup,
    }) async {
      final harness = TestAttentionHarness(
        context: const BeaconNotificationContext(beaconAuthorId: 'author'),
      );
      final intent = await harness.intents.helpOfferSubmitted(
        beaconId: 'B1',
        helpOffererId: 'helper',
        authorId: 'author',
        sourceEventKey: 'offer:B1:helper',
        isBackupOffer: backup,
      );
      return payloadFor(intent, 'author');
    }

    test('a backup offer is stored as a JSON bool true', () async {
      expect((await authorPayload(backup: true))['isBackupOffer'], isTrue);
    });

    test('a regular offer is not marked as a backup', () async {
      expect(
        (await authorPayload(backup: false))['isBackupOffer'],
        anyOf(isNull, isFalse),
      );
    });
  });

  group('plan step notices', () {
    for (final (eventType, minutes) in [
      (AttentionEventType.planStepReminder, 15),
      (AttentionEventType.planStepLate, 45),
    ]) {
      test('${eventType.name} stores the offset as an integer', () async {
        final harness = TestAttentionHarness();

        final intent = await harness.intents.planEvent(
          eventType: eventType,
          beaconId: 'B1',
          beaconTitle: 'Fix the roof',
          actorUserId: null,
          recipients: {'assignee': AttentionRecipientReason.planStepAssignee},
          sourceEventKey: 'plan:${eventType.name}:S1',
          stepId: 'S1',
          stepTitle: 'Bring ladder',
          relativeMinutes: minutes,
        );

        expect(payloadFor(intent, 'assignee')['relativeMinutes'], minutes);
      });
    }
  });
}

/// Delivers one hierarchy event to one target and records nothing else.
final class _DeliveryOutbox extends Fake implements BeaconHierarchyOutboxPort {
  _DeliveryOutbox({
    required this.event,
    required this.targetBeaconId,
    required this.direction,
  });

  final BeaconHierarchyEvent event;
  final String targetBeaconId;
  final BeaconHierarchyDeliveryDirection direction;

  @override
  Future<List<BeaconHierarchyDeliveryTarget>> claimDueDeliveries({
    required String leaseOwner,
    required DateTime now,
    required int limit,
  }) async => [
    BeaconHierarchyDeliveryTarget(
      eventId: event.eventId,
      targetBeaconId: targetBeaconId,
      direction: direction,
    ),
  ];

  @override
  Future<BeaconHierarchyEvent?> loadEvent(String eventId) async => event;

  @override
  Future<BeaconStatus?> loadDestinationBeaconStatus(String beaconId) async =>
      BeaconStatus.open;

  @override
  Future<BeaconKind?> loadDestinationBeaconKind(String beaconId) async =>
      BeaconKind.request;

  @override
  Future<String?> loadBeaconTitle(String beaconId) async => null;

  @override
  Future<String> insertHierarchyLifecycleNotice({
    required String eventId,
    required String targetBeaconId,
    required BeaconHierarchyDeliveryDirection direction,
    required BeaconStatus toStatus,
    required DateTime occurredAt,
    required String noticeBody,
    required bool sourceDeleted,
    String? sourceTitle,
  }) async => 'R-notice';

  @override
  Future<void> markDeliveryDelivered({
    required String eventId,
    required String targetBeaconId,
    required String leaseOwner,
    String? noticeMessageId,
  }) async {}
}
