import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/port/attention_expiry_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_expiry_sweep_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/test_attention_harness.dart';

class _ExpiryRepository extends Fake implements AttentionExpiryRepositoryPort {
  List<String> due = const [];

  @override
  Future<List<String>> lockExpiredReviewWindowBeaconIds(DateTime now) async =>
      due;
}

class _EvaluationRepository extends Fake implements EvaluationRepositoryPort {
  final calls = <({String beaconId, String reason, String? actorUserId})>[];

  @override
  Future<void> closeBeaconReviewWindow(
    String beaconId, {
    required String reason,
    String? actorUserId,
  }) async {
    calls.add((
      beaconId: beaconId,
      reason: reason,
      actorUserId: actorUserId,
    ));
  }
}

void main() {
  const beaconId = 'Bexpired';

  test(
    'closes and records each expired window with an actor-null intent',
    () async {
      final expiry = _ExpiryRepository()..due = const [beaconId];
      final evaluation = _EvaluationRepository();
      final attention = TestAttentionHarness(
        context: const BeaconNotificationContext(
          beaconAuthorId: 'Uauthor',
          admittedUserIds: {'Uhelper'},
          inboxStanceUserIds: {'Uwatcher'},
        ),
        onContextLoaded: () => expect(evaluation.calls, isEmpty),
      );
      final case_ = AttentionExpirySweepCase(
        expiry,
        evaluation,
        attention.intents,
        attention.transactional,
        Env(
          environment: Environment.test,
          attentionV1NewProducersEnabled: true,
        ),
      );

      expect(await case_.runDue(now: DateTime.utc(2026)), 1);

      expect(evaluation.calls, [
        (
          beaconId: beaconId,
          reason: BeaconLifecycleChangeReason.reviewExpired,
          actorUserId: null,
        ),
      ]);
      final intent = attention.recorded.single;
      expect(intent.eventType, AttentionEventType.requestStatusChanged);
      expect(intent.actorUserId, isNull);
      expect(intent.recipients, hasLength(3));
    },
  );

  test('disabled producer gate is a zero-side-effect no-op', () async {
    final expiry = _ExpiryRepository()..due = const [beaconId];
    final evaluation = _EvaluationRepository();
    final attention = TestAttentionHarness();
    final case_ = AttentionExpirySweepCase(
      expiry,
      evaluation,
      attention.intents,
      attention.transactional,
      Env(
        environment: Environment.test,
        attentionV1NewProducersEnabled: false,
      ),
    );

    expect(await case_.runDue(), 0);
    expect(evaluation.calls, isEmpty);
    expect(attention.recorded, isEmpty);
  });
}
