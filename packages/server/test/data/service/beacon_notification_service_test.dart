import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/data/service/beacon_notification_service.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/data/service/push_action_token_service.dart';
import 'package:tentura_server/domain/notification/plan_push_policy.dart';
import 'package:tentura_server/domain/plan/push_action.dart';
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

import '../../support/test_attention_harness.dart';

typedef _EmailConsider = ({
  String recipientUserId,
  NotificationKind? kind,
  String beaconId,
  String channelCollapseKey,
  String title,
  String body,
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

class _RuPrefs extends _FakePrefs {
  @override
  Future<NotificationPreferencesEntity> getForAccount(String accountId) async =>
      NotificationPreferencesEntity.defaults(accountId).copyWith(locale: 'ru');
}

class _RuLockScreenSafePrefs extends _FakePrefs {
  @override
  Future<NotificationPreferencesEntity> getForAccount(String accountId) async =>
      NotificationPreferencesEntity.defaults(
        accountId,
      ).copyWith(locale: 'ru', lockScreenSafe: true);
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
      title: title,
      body: body,
      pushDelivered: pushDelivered,
    ));
  }

  @override
  Future<bool> considerImmediateByCategory({
    required String recipientUserId,
    required String channelCollapseKey,
    required String title,
    required String body,
    required String actionUrl,
    required String categoryScope,
  }) async {
    considers.add((
      recipientUserId: recipientUserId,
      kind: null,
      beaconId: '',
      channelCollapseKey: channelCollapseKey,
      title: title,
      body: body,
      pushDelivered: false,
    ));
    return false;
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
    PushActionTokenService? pushActionTokens,
    NotificationPreferenceRepositoryPort? preferences,
  }) => BeaconNotificationService(
    fcmBatch ?? _FakeFcmBatch(),
    fcmTokens ?? _FakeFcmTokens(),
    fcmRemote ?? _FakeFcmRemote(),
    preferences ?? _FakePrefs(),
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
    String title = 'Title',
    String body = 'Body',
    String? actorDisplayName,
  }) => AttentionChannelDecision(
    coordinationItemId: coordinationItemId,
    receiptId: 'receipt-1',
    recipientId: recipientId,
    kind: kind,
    priority: NotificationPriority.normal,
    title: title,
    body: body,
    actionUrl: '/action',
    dedupKey: dedupKey,
    actorUserId: actorUserId,
    reason: 'test',
    beaconId: beaconId,
    actorDisplayName: actorDisplayName,
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
      final signer = PushActionTokenService(Env());
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
        pushActionTokens: PushActionTokenService(Env()),
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
        pushActionTokens: PushActionTokenService(Env()),
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
        tokens: PushActionTokenService(Env()),
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
        tokens: PushActionTokenService(Env()),
        planRepository: null,
      );
      expect(buttons.actions, isEmpty);
      expect(buttons.token, isNull);
    });
  });
  // #367: a Russian reader's push is Russian, the title included.
  group('recipient language', () {
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

    Future<FcmNotificationEntity> pushFor(
      AttentionChannelDecision d, {
      required NotificationPreferenceRepositoryPort preferences,
    }) async {
      final batch = _CapturingFcmBatch();
      final service = build(
        fcmBatch: batch,
        fcmTokens: tokens(),
        preferences: preferences,
      );
      await service.handOffChannels([d]);
      return batch.enqueues.single.message;
    }

    test('an accepted offer reads in Russian, title and body', () async {
      final message = await pushFor(
        decision(
          kind: NotificationKind.roomAccess,
          title: 'Anna accepted your offer',
          actorDisplayName: 'Anna',
          body: 'Your offer was accepted',
        ),
        preferences: _RuPrefs(),
      );

      expect(message.title, 'Anna принял(а) ваше предложение');
      expect(message.body, 'Ваше предложение принято');
    });

    test('words a person wrote stay as written', () async {
      final message = await pushFor(
        decision(
          kind: NotificationKind.roomAccess,
          title: 'Anna accepted your offer',
          actorDisplayName: 'Anna',
          body: 'Hikes — see you at 9',
        ),
        preferences: _RuPrefs(),
      );

      expect(message.title, 'Anna принял(а) ваше предложение');
      expect(message.body, 'Hikes — see you at 9');
    });

    test('an English reader gets the stored copy', () async {
      final message = await pushFor(
        decision(
          kind: NotificationKind.roomAccess,
          title: 'Anna accepted your offer',
          actorDisplayName: 'Anna',
          body: 'Your offer was accepted',
        ),
        preferences: _FakePrefs(),
      );

      expect(message.title, 'Anna accepted your offer');
      expect(message.body, 'Your offer was accepted');
    });

    test(
      'the title is translated only for the actor stored on the job',
      () async {
        final message = await pushFor(
          decision(
            kind: NotificationKind.roomAccess,
            title: 'Anna accepted your offer',
            body: 'Your offer was accepted',
            actorDisplayName: 'Boris',
          ),
          preferences: _RuPrefs(),
        );

        expect(message.title, 'Anna accepted your offer');
        expect(message.body, 'Ваше предложение принято');
      },
    );

    // #367 review r2: the job carries the actor name each builder used, so
    // the copy a builder wrote with the actor's name in it can be rebuilt in
    // the reader's language. The harness actor is called «Actor».
    group('copy straight from the intent builders', () {
      final harness = TestAttentionHarness();

      AttentionChannelDecision fromIntent(AttentionDispatchIntent intent) =>
          decision(
            kind: intent.kind,
            title: intent.title,
            body: intent.body,
            actorDisplayName: intent.actorDisplayName,
          );

      test('a mention with no text reads in Russian', () async {
        final intent = await harness.intents.roomMentioned(
          beaconId: 'beacon-1',
          messageId: 'message-1',
          actorUserId: 'actor',
          recipientUserIds: const {recipientId},
          excerpt: '',
          sourceEventKey: 'mention:1',
        );

        final message = await pushFor(
          fromIntent(intent),
          preferences: _RuPrefs(),
        );

        expect(message.title, 'Actor');
        expect(message.body, 'Actor упомянул(а) вас');
      });

      test('a first reply to a post with no text reads in Russian', () async {
        final intent = await harness.intents.postFirstResponse(
          beaconId: 'beacon-1',
          messageId: 'message-1',
          actorUserId: 'actor',
          authorUserId: recipientId,
          excerpt: '',
          sourceEventKey: 'first-response:1',
        );

        final message = await pushFor(
          fromIntent(intent),
          preferences: _RuPrefs(),
        );

        expect(message.title, 'Actor');
        expect(message.body, 'Actor откликнулся на ваш пост');
      });

      test('a mention with text keeps the text', () async {
        final intent = await harness.intents.roomMentioned(
          beaconId: 'beacon-1',
          messageId: 'message-1',
          actorUserId: 'actor',
          recipientUserIds: const {recipientId},
          excerpt: 'See you at 9',
          sourceEventKey: 'mention:2',
        );

        final message = await pushFor(
          fromIntent(intent),
          preferences: _RuPrefs(),
        );

        expect(message.title, 'Actor');
        expect(message.body, 'See you at 9');
      });

      test('builders that name the actor store the name on the job', () async {
        final declined = await harness.intents.forwardDeclined(
          beaconId: 'beacon-1',
          declinerUserId: 'actor',
          authorId: recipientId,
          sourceEventKey: 'declined:1',
        );
        final connected = await harness.intents.mutualConnectionFormed(
          actorUserId: 'actor',
          counterpartUserId: recipientId,
          sourceEventKey: 'connected:1',
        );

        expect(declined.body, "Actor can't help");
        expect(declined.actorDisplayName, 'Actor');
        expect(connected.body, 'You and Actor are now connected.');
        expect(connected.actorDisplayName, 'Actor');
      });
    });
  });

  // #367: the email a Russian reader gets carries the Russian sentence, not
  // the stored English one inside a Russian frame.
  group('recipient language in email', () {
    Future<_EmailConsider> emailFor(
      AttentionChannelDecision d, {
      required NotificationPreferenceRepositoryPort preferences,
    }) async {
      final email = _CapturingEmail();
      final service = build(email: email, preferences: preferences);
      await service.handOffChannels([d]);
      return email.considers.single;
    }

    test('an accepted offer emails in Russian, title and body', () async {
      final sent = await emailFor(
        decision(
          kind: NotificationKind.roomAccess,
          title: 'Anna accepted your offer',
          body: 'Your offer was accepted',
          actorDisplayName: 'Anna',
        ),
        preferences: _RuPrefs(),
      );

      expect(sent.title, 'Anna принял(а) ваше предложение');
      expect(sent.body, 'Ваше предложение принято');
    });

    test('a lock-screen-safe reader still gets the full email copy', () async {
      final sent = await emailFor(
        decision(
          kind: NotificationKind.roomAccess,
          title: 'Anna accepted your offer',
          body: 'Hikes — see you at 9',
          actorDisplayName: 'Anna',
        ),
        preferences: _RuLockScreenSafePrefs(),
      );

      expect(sent.title, 'Anna принял(а) ваше предложение');
      expect(sent.body, 'Hikes — see you at 9');
    });

    test('an accepted invitation emails in Russian', () async {
      final sent = await emailFor(
        decision(
          kind: NotificationKind.inviteAccepted,
          title: 'Invitation accepted',
          body: 'Anna accepted your invitation',
          actorDisplayName: 'Anna',
        ),
        preferences: _RuPrefs(),
      );

      expect(sent.kind, isNull, reason: 'the connections email path');
      expect(sent.title, 'Приглашение принято');
      expect(sent.body, 'Anna принял(а) ваше приглашение');
    });

    test('an English reader is emailed the stored copy', () async {
      final sent = await emailFor(
        decision(
          kind: NotificationKind.roomAccess,
          title: 'Anna accepted your offer',
          body: 'Your offer was accepted',
          actorDisplayName: 'Anna',
        ),
        preferences: _FakePrefs(),
      );

      expect(sent.title, 'Anna accepted your offer');
      expect(sent.body, 'Your offer was accepted');
    });
  });
}
