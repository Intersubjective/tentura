import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_event.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_hierarchy_delivery_consts.dart';
import 'package:tentura_server/domain/policy/beacon_hierarchy_notice_copy.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '_use_case_base.dart';

/// Bounded hierarchy lifecycle delivery worker (§4.4).
@LazySingleton()
final class BeaconHierarchyDeliveryCase extends UseCaseBase {
  BeaconHierarchyDeliveryCase(
    this._outbox,
    this._attention,
    this._intents, {
    required super.env,
    required super.logger,
  });

  final BeaconHierarchyOutboxPort _outbox;
  final TransactionalAttentionCase _attention;
  final AttentionIntentCase _intents;

  static const batchLimit = 50;

  Future<void> runDue({required String workerId, required DateTime now}) async {
    final claimed = await _outbox.claimDueDeliveries(
      leaseOwner: workerId,
      now: now,
      limit: batchLimit,
    );
    if (claimed.isEmpty) {
      return;
    }

    var delivered = 0;
    var suppressed = 0;
    var failed = 0;

    for (final target in claimed) {
      try {
        final outcome = await _processTarget(
          target: target,
          workerId: workerId,
        );
        switch (outcome) {
          case _TargetOutcome.delivered:
            delivered++;
          case _TargetOutcome.suppressed:
            suppressed++;
        }
      } on Object catch (error, stackTrace) {
        failed++;
        final safeCode = BeaconHierarchyDeliverySafeError.classify(error);
        final attemptCount =
            await _outbox.loadDeliveryAttemptCount(
              eventId: target.eventId,
              targetBeaconId: target.targetBeaconId,
            ) ??
            BeaconHierarchyDeliverySafeError.poisonAttemptThreshold;
        await _outbox.scheduleDeliveryRetry(
          eventId: target.eventId,
          targetBeaconId: target.targetBeaconId,
          leaseOwner: workerId,
          now: now,
          attemptCount: attemptCount,
          safeErrorCode: safeCode,
        );
        if (attemptCount >= BeaconHierarchyDeliverySafeError.poisonAttemptThreshold) {
          logger.warning(
            'beacon hierarchy delivery poison threshold reached '
            'event=${target.eventId} target=${target.targetBeaconId} '
            'attempts=$attemptCount code=$safeCode',
          );
        } else {
          logger.info(
            'beacon hierarchy delivery retry scheduled '
            'event=${target.eventId} target=${target.targetBeaconId} '
            'attempts=$attemptCount code=$safeCode',
          );
        }
        logger.fine('beacon hierarchy delivery failure', error, stackTrace);
      }
    }

    logger.info(
      'beacon hierarchy delivery sweep worker=$workerId '
      'claimed=${claimed.length} delivered=$delivered '
      'suppressed=$suppressed failed=$failed',
    );
  }

  /// Explicit audited operator action — never invoked by [runDue].
  Future<bool> parkPoisonedDeliveryAsOperator({
    required String eventId,
    required String targetBeaconId,
    required String operatorId,
  }) async {
    final parked = await _outbox.operatorParkPoisonedDelivery(
      eventId: eventId,
      targetBeaconId: targetBeaconId,
    );
    if (parked) {
      logger.warning(
        'beacon hierarchy delivery operator parked '
        'event=$eventId target=$targetBeaconId operator=$operatorId',
      );
    }
    return parked;
  }

  Future<_TargetOutcome> _processTarget({
    required BeaconHierarchyDeliveryTarget target,
    required String workerId,
  }) async {
    return _attention.runAction(
      actorUserId: null,
      action: (transaction) async {
        final event = await _outbox.loadEvent(target.eventId);
        if (event == null) {
          throw StateError('hierarchy event missing');
        }

        final destinationStatus = await _outbox.loadDestinationBeaconStatus(
          target.targetBeaconId,
        );
        if (destinationStatus == null ||
            destinationStatus == BeaconStatus.deleted) {
          await _outbox.markDeliverySuppressed(
            eventId: target.eventId,
            targetBeaconId: target.targetBeaconId,
            leaseOwner: workerId,
          );
          return _TargetOutcome.suppressed;
        }

        final sourceStatus = await _outbox.loadDestinationBeaconStatus(
          event.sourceBeaconId,
        );
        final sourceDeleted = sourceStatus == BeaconStatus.deleted;
        final direction = _directionFromWire(target.direction);
        final noticeBody = BeaconHierarchyNoticeCopy.noticeBody(
          direction: direction,
          toStatus: event.toStatus,
          occurredAt: event.occurredAt,
          sourceDeleted: sourceDeleted,
        );

        final noticeMessageId = await _outbox.insertHierarchyLifecycleNotice(
          eventId: target.eventId,
          targetBeaconId: target.targetBeaconId,
          direction: direction,
          toStatus: event.toStatus,
          occurredAt: event.occurredAt,
          noticeBody: noticeBody,
          sourceDeleted: sourceDeleted,
        );

        final occurrenceKey = 'hierarchy:${target.eventId}:${target.targetBeaconId}';
        final intent = await _intents.beaconHierarchyStatusChanged(
          destinationBeaconId: target.targetBeaconId,
          messageId: noticeMessageId,
          direction: direction,
          toStatus: event.toStatus,
          occurredAt: event.occurredAt,
          sourceEventKey: occurrenceKey,
          sourceDeleted: sourceDeleted,
          actorUserId: event.actorUserId,
        );
        if (intent.recipients.isNotEmpty) {
          await transaction.record(intent);
        }

        await _outbox.markDeliveryDelivered(
          eventId: target.eventId,
          targetBeaconId: target.targetBeaconId,
          leaseOwner: workerId,
          noticeMessageId: noticeMessageId,
        );
        return _TargetOutcome.delivered;
      },
    );
  }

  BeaconHierarchyDeliveryDirection _directionFromWire(
    BeaconHierarchyDeliveryDirection direction,
  ) => direction;
}

enum _TargetOutcome { delivered, suppressed }
