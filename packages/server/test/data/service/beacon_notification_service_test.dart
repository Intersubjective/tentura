import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/data/service/beacon_notification_service.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/plan/push_action_token.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/fcm_batch_queue_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/env.dart';

typedef _EmailConsider = ({
  String recipientUserId,
  NotificationKind kind,
  String beaconId,
  String channelCollapseKey,
  bool pushDelivered,
});

typedef _FcmBatchEnqueue = ({
  String receiverId,
  Set<String> fcmTokens,
  FcmNotificationEntity message,
});

class _FakeFcmBatch implements FcmBatchQueuePort {
  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _CapturingFcmBatch implements FcmBatchQueuePort {
  final enqueues = <_FcmBatchEnqueue>[];

  @override
  void enqueue({
    required String receiverId,
    required Set<String> fcmTokens,
    required FcmNotificationEntity message,
  }) {
    enqueues.add((
      receiverId: receiverId,
      fcmTokens: fcmTokens,
      message: message,
    ));
  }

  @override
  void dispose() {}
}

class _FakeFcmTokens implements FcmTokenRepositoryPort {
  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeFcmTokensForUser implements FcmTokenRepositoryPort {
  _FakeFcmTokensForUser(this.userId, this.tokens);

  final String userId;
  final Iterable<FcmTokenEntity> tokens;

  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String id) async =>
      id == userId ? tokens : const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeFcmRemote implements FcmRemoteRepositoryPort {
  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required dynamic message,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _CapturingFcmRemote implements FcmRemoteRepositoryPort {
  final sent = <FcmNotificationEntity>[];

  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) async {
    sent.add(message);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakePrefs implements NotificationPreferenceRepositoryPort {
  @override
  Future<NotificationPreferencesEntity> getForAccount(String accountId) async =>
      NotificationPreferencesEntity.defaults(accountId);

  @override
  Future<Set<String>> getMutedBeaconIds(String accountId, DateTime now) async =>
      const {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _CapturingEmail implements EmailNotificationPort {
  final considers = <_EmailConsider>[];

  @override
  Future<void> considerImmediate({
    required String recipientUserId,
    required NotificationKind kind,
    required String beaconId,
    required String channelCollapseKey,
    required String title,
    required String body,
    required String actionUrl,
    required bool pushDelivered,
  }) async {
    considers.add((
      recipientUserId: recipientUserId,
      kind: kind,
      beaconId: beaconId,
      channelCollapseKey: channelCollapseKey,
      pushDelivered: pushDelivered,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  BeaconNotificationService build({
    _CapturingEmail? email,
    FcmBatchQueuePort? fcmBatch,
    FcmTokenRepositoryPort? fcmTokens,
    FcmRemoteRepositoryPort? fcmRemote,
    PushActionToken? pushActionTokens,
  }) => BeaconNotificationService(
    fcmBatch ?? _FakeFcmBatch(),
    fcmTokens ?? _FakeFcmTokens(),
    fcmRemote ?? _FakeFcmRemote(),
    _FakePrefs(),
    email ?? _CapturingEmail(),
    Logger('test'),
    pushActionTokens: pushActionTokens,
  );

  AttentionChannelDecision decision({
    required NotificationKind kind,
    String recipientId = 'recipient-1',
    String beaconId = 'beacon-1',
    String dedupKey = 'recipient-1|asksOfMe|beacon-1|',
    String actorUserId = 'actor',
    String? coordinationItemId,
  }) => AttentionChannelDecision(
    coordinationItemId: coordinationItemId,
    receiptId: 'receipt-1',
    recipientId: recipientId,
    kind: kind,
    priority: NotificationPriority.normal,
    title: 'Title',
    body: 'Body',
    actionUrl: '/action',
    dedupKey: dedupKey,
    actorUserId: actorUserId,
    reason: 'test',
    beaconId: beaconId,
  );

  group('handOffChannels push delivery', () {
    test('queues FCM when recipient has a device token', () async {
      const recipientId = 'recipient-1';
      final email = _CapturingEmail();
      final batch = _CapturingFcmBatch();
      final service = build(
        email: email,
        fcmBatch: batch,
        fcmTokens: _FakeFcmTokensForUser(
          recipientId,
          [
            FcmTokenEntity(
              userId: recipientId,
              appId: const Uuid().v4obj(),
              platform: 'test',
              token: 'tok-1',
              createdAt: DateTime.utc(2026),
              lastRefreshedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );

      await service.handOffChannels([
        decision(kind: NotificationKind.needsMe, recipientId: recipientId),
      ]);

      expect(batch.enqueues, hasLength(1));
      expect(batch.enqueues.single.receiverId, recipientId);
      expect(batch.enqueues.single.fcmTokens, {'tok-1'});
      expect(email.considers.single.pushDelivered, isTrue);
    });

    test(
      'email fallback sees pushDelivered false without device token',
      () async {
        final email = _CapturingEmail();
        final service = build(email: email);

        await service.handOffChannels([
          decision(kind: NotificationKind.needsMe),
        ]);

        expect(email.considers.single.pushDelivered, isFalse);
      },
    );

    test('passes dedup key through to email fallback', () async {
      final email = _CapturingEmail();
      final service = build(email: email);
      const dedupKey = 'recipient-1|asksOfMe|beacon-1|';

      await service.handOffChannels([
        decision(kind: NotificationKind.needsMe, dedupKey: dedupKey),
      ]);

      expect(email.considers.single.channelCollapseKey, dedupKey);
    });
  });

  group('plan obligation pushes (#220 §5.9)', () {
    const recipientId = 'recipient-1';
    FcmTokenRepositoryPort tokens() => _FakeFcmTokensForUser(recipientId, [
      FcmTokenEntity(
        userId: recipientId,
        appId: const Uuid().v4obj(),
        platform: 'web',
        token: 'tok-1',
        createdAt: DateTime.utc(2026),
        lastRefreshedAt: DateTime.utc(2026),
      ),
    ]);

    test('a due step bypasses the batch queue and carries buttons, a '
        'signed token, a per-step tag, TTL and high urgency', () async {
      final batch = _CapturingFcmBatch();
      final remote = _CapturingFcmRemote();
      final signer = PushActionToken(Env());
      final email = _CapturingEmail();
      final service = build(
        email: email,
        fcmBatch: batch,
        fcmTokens: tokens(),
        fcmRemote: remote,
        pushActionTokens: signer,
      );

      await service.handOffChannels([
        decision(
          kind: NotificationKind.planStepDue,
          coordinationItemId: 'PS000000000001',
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(batch.enqueues, isEmpty);
      final message = remote.sent.single;
      expect(message.actions.map((a) => a.id), ['done', 'open']);
      expect(message.tag, 'plan:PS000000000001');
      expect(message.stepId, 'PS000000000001');
      expect(message.urgency, 'high');
      expect(message.ttlSeconds, 3600);
      expect(message.actionFeedback, isNotNull);
      final claims = signer.verify(message.actionToken!)!;
      expect(claims.accountId, recipientId);
      expect(claims.action, PushAction.done);
      expect(claims.stepId, 'PS000000000001');
      expect(claims.beaconId, 'beacon-1');
      expect(email.considers.single.pushDelivered, isTrue);
    });

    test('«your turn» goes direct without buttons', () async {
      final batch = _CapturingFcmBatch();
      final remote = _CapturingFcmRemote();
      final service = build(
        fcmBatch: batch,
        fcmTokens: tokens(),
        fcmRemote: remote,
        pushActionTokens: PushActionToken(Env()),
      );

      await service.handOffChannels([
        decision(
          kind: NotificationKind.planStepTurn,
          coordinationItemId: 'PS000000000001',
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(batch.enqueues, isEmpty);
      expect(remote.sent.single.actions, isEmpty);
      expect(remote.sent.single.actionToken, isNull);
    });

    test('ambient plan kinds still go through the batch queue', () async {
      final batch = _CapturingFcmBatch();
      final service = build(
        fcmBatch: batch,
        fcmTokens: tokens(),
        pushActionTokens: PushActionToken(Env()),
      );

      await service.handOffChannels([
        decision(kind: NotificationKind.planCantMake),
      ]);

      expect(batch.enqueues, hasLength(1));
    });

    test('Russian buttons and feedback', () async {
      final buttons = await planPushButtons(
        kind: NotificationKind.planStepOverdue,
        recipientId: recipientId,
        beaconId: 'beacon-1',
        stepId: 'PS000000000001',
        locale: 'ru',
        tokens: PushActionToken(Env()),
        planRepository: null,
      );
      expect(buttons.actions.map((a) => a.title), ['Готово', 'Открыть']);
      expect(planPushFeedback('ru').failed, 'Не получилось — откройте шаг');
      expect(planPushTtlSeconds(NotificationKind.planStepReminder), 900);
    });

    test('«Понятно» needs the plan head; none without it', () async {
      final buttons = await planPushButtons(
        kind: NotificationKind.planChangePending,
        recipientId: recipientId,
        beaconId: 'beacon-1',
        stepId: null,
        locale: 'en',
        tokens: PushActionToken(Env()),
        planRepository: null,
      );
      expect(buttons.actions, isEmpty);
      expect(buttons.token, isNull);
    });
  });
}
