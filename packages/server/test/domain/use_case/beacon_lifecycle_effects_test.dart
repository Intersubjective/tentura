import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/recording_beacon_hierarchy_outbox.dart';

void main() {
  late RecordingBeaconHierarchyOutbox outbox;
  late BeaconLifecycleEffectsCase case_;

  setUp(() {
    outbox = RecordingBeaconHierarchyOutbox();
    case_ = BeaconLifecycleEffectsCase(
      outbox,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconLifecycleEffectsTest'),
    );
  });

  test('eligible cancel transition records event and topology targets', () async {
    final event = await case_.recordEligibleSourceTransition(
      sourceBeaconId: 'B-source',
      fromStatus: BeaconStatus.open,
      toStatus: BeaconStatus.cancelled,
      occurredAt: DateTime.utc(2026, 3, 1),
      actorUserId: 'U-actor',
      reason: BeaconStatusTransitionReason.cancelled,
    );

    expect(event, isNotNull);
    expect(outbox.recordedEvents, hasLength(1));
    expect(outbox.recordedEvents.single.toStatus, BeaconStatus.cancelled);
    expect(outbox.topologyInserts, hasLength(1));
    expect(outbox.topologyInserts.single.sourceBeaconId, 'B-source');
  });

  test('noop transition records nothing', () async {
    final event = await case_.recordEligibleSourceTransition(
      sourceBeaconId: 'B-source',
      fromStatus: BeaconStatus.open,
      toStatus: BeaconStatus.open,
      occurredAt: DateTime.utc(2026, 3, 1),
      actorUserId: 'U-actor',
    );

    expect(event, isNull);
    expect(outbox.recordedEvents, isEmpty);
    expect(outbox.topologyInserts, isEmpty);
  });

  test('local reopen records nothing', () async {
    final event = await case_.recordEligibleSourceTransition(
      sourceBeaconId: 'B-source',
      fromStatus: BeaconStatus.reviewOpen,
      toStatus: BeaconStatus.open,
      occurredAt: DateTime.utc(2026, 3, 1),
      actorUserId: 'U-actor',
      reason: BeaconStatusTransitionReason.reopenedFromReview,
    );

    expect(event, isNull);
    expect(outbox.recordedEvents, isEmpty);
  });

  test('review window open and final close are separate eligible events', () async {
    final wrappingUp = await case_.recordEligibleSourceTransition(
      sourceBeaconId: 'B-source',
      fromStatus: BeaconStatus.open,
      toStatus: BeaconStatus.reviewOpen,
      occurredAt: DateTime.utc(2026, 3, 1, 10),
      actorUserId: 'U-actor',
      reason: BeaconStatusTransitionReason.reviewWindowOpened,
    );
    final closed = await case_.recordEligibleSourceTransition(
      sourceBeaconId: 'B-source',
      fromStatus: BeaconStatus.reviewOpen,
      toStatus: BeaconStatus.closed,
      occurredAt: DateTime.utc(2026, 3, 8, 10),
      actorUserId: 'U-actor',
      reason: BeaconStatusTransitionReason.reviewExpired,
    );

    expect(wrappingUp, isNotNull);
    expect(closed, isNotNull);
    expect(outbox.recordedEvents, hasLength(2));
    expect(outbox.recordedEvents[0].sourceSequence, 1);
    expect(outbox.recordedEvents[1].sourceSequence, 2);
    expect(outbox.recordedEvents[0].toStatus, BeaconStatus.reviewOpen);
    expect(outbox.recordedEvents[1].toStatus, BeaconStatus.closed);
  });

  test('re-close after local reopen gets a fresh sequence', () async {
    await case_.recordEligibleSourceTransition(
      sourceBeaconId: 'B-source',
      fromStatus: BeaconStatus.open,
      toStatus: BeaconStatus.reviewOpen,
      occurredAt: DateTime.utc(2026, 3, 1),
      actorUserId: 'U-actor',
      reason: BeaconStatusTransitionReason.reviewWindowOpened,
    );
    await case_.recordEligibleSourceTransition(
      sourceBeaconId: 'B-source',
      fromStatus: BeaconStatus.reviewOpen,
      toStatus: BeaconStatus.open,
      occurredAt: DateTime.utc(2026, 3, 2),
      actorUserId: 'U-actor',
      reason: BeaconStatusTransitionReason.reopenedFromReview,
    );
    final reclose = await case_.recordEligibleSourceTransition(
      sourceBeaconId: 'B-source',
      fromStatus: BeaconStatus.reviewOpen,
      toStatus: BeaconStatus.closed,
      occurredAt: DateTime.utc(2026, 3, 9),
      actorUserId: 'U-actor',
      reason: BeaconStatusTransitionReason.authorCloseNow,
    );

    expect(reclose, isNotNull);
    expect(outbox.recordedEvents, hasLength(2));
    expect(outbox.recordedEvents.last.sourceSequence, 2);
    expect(outbox.recordedEvents.last.toStatus, BeaconStatus.closed);
  });
}
