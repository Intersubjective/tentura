import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/data/service/beacon_notification_service.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/fcm_batch_queue_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';

// A pair «took it» receipt, delivered as a push and an immediate email: the
// copy names the visible co-taker, falls back to the solo sentence when the
// co-taker is hidden or blocked, and a solo receipt asks identity only once.

const _recipient = 'Urecipient';
const _partner = 'Upartner';
const _taker = 'Utaker';

class _Identity implements NotificationIdentityPort {
  _Identity({this.partnerName = 'Bob', this.partnerHidden = false});

  final String? partnerName;
  final bool partnerHidden;
  final requests = <IdentityRequest>[];

  @override
  Future<List<NotificationIdentity>> resolve(
    String recipientId,
    List<IdentityRequest> asked,
  ) async {
    requests.addAll(asked);
    return [
      for (final r in asked)
        NotificationIdentity(
          entityKind: NotificationEntityKind.request,
          label: 'Fix the roof',
          tombstone: false,
          readable: true,
          actorName: r.actorId == _partner ? partnerName : 'Alice',
          actorHidden: r.actorId == _partner && partnerHidden,
          relatedLabel: null,
          expired: false,
        ),
    ];
  }
}

class _Email implements EmailNotificationPort {
  final copies = <NotificationCopy?>[];

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
    NotificationCopy? copy,
  }) async => copies.add(copy);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _Batch implements FcmBatchQueuePort {
  final messages = <FcmNotificationEntity>[];

  @override
  void enqueue({
    required String receiverId,
    required Set<String> fcmTokens,
    required FcmNotificationEntity message,
  }) => messages.add(message);

  @override
  void dispose() {}
}

class _Tokens implements FcmTokenRepositoryPort {
  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String id) async => [
    FcmTokenEntity(
      userId: id,
      appId: const Uuid().v4obj(),
      platform: 'test',
      token: 'tok',
      createdAt: DateTime.utc(2026),
      lastRefreshedAt: DateTime.utc(2026),
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _Remote implements FcmRemoteRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _Prefs implements NotificationPreferenceRepositoryPort {
  _Prefs(this.locale);
  final String locale;

  @override
  Future<NotificationPreferencesEntity> getForAccount(String id) async =>
      NotificationPreferencesEntity.defaults(id).copyWith(locale: locale);

  @override
  Future<Set<String>> getMutedBeaconIds(String id, DateTime now) async =>
      const {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

AttentionChannelDecision _takenReceipt({bool pair = true}) =>
    AttentionChannelDecision(
      receiptId: 'receipt-1',
      recipientId: _recipient,
      kind: NotificationKind.batonTaken,
      priority: NotificationPriority.normal,
      title: 'stored title',
      body: 'stored body',
      actionUrl: '/action',
      dedupKey: 'baton_taken:L1',
      actorUserId: _taker,
      reason: 'test',
      presentationKey: 'baton_taken',
      presentationPayload: {
        'excerpt': 'Bring the ladder',
        if (pair) 'withUserId': _partner,
      },
      beaconId: 'beacon-1',
    );

typedef _Delivered = ({
  String pushBody,
  String pushTitle,
  String emailHeadline,
  String emailSentence,
});

void main() {
  Future<_Delivered> deliver(
    AttentionChannelDecision decision, {
    required _Identity identity,
    String locale = 'en',
  }) async {
    final email = _Email();
    final batch = _Batch();
    final service = BeaconNotificationService(
      batch,
      _Tokens(),
      _Remote(),
      _Prefs(locale),
      email,
      Logger('test'),
      identity: identity,
    );
    await service.handOffChannels([decision]);
    expect(batch.messages, hasLength(1), reason: 'one push queued');
    expect(email.copies, hasLength(1), reason: 'one immediate email');
    return (
      pushTitle: batch.messages.single.title,
      pushBody: batch.messages.single.body,
      emailHeadline: email.copies.single!.headline,
      emailSentence: email.copies.single!.sentence,
    );
  }

  group('pair «took it» delivery names the co-taker', () {
    test(
      'a visible co-taker is asked for by a second identity request',
      () async {
        final identity = _Identity();
        await deliver(_takenReceipt(), identity: identity);

        expect(identity.requests.map((r) => r.actorId), contains(_partner));
        expect(identity.requests.map((r) => r.actorId), contains(_taker));
      },
    );

    test('push and email read «You and Bob took it» in English', () async {
      final r = await deliver(_takenReceipt(), identity: _Identity());

      expect(r.pushTitle, 'Fix the roof');
      expect(r.emailHeadline, 'You took it');
      expect(r.pushBody, 'You and Bob took it: Bring the ladder');
      expect(r.emailSentence, 'You and Bob took it: Bring the ladder');
    });

    test('push and email read «Вы и Bob взялись» in Russian', () async {
      final r = await deliver(
        _takenReceipt(),
        identity: _Identity(),
        locale: 'ru',
      );

      expect(r.emailHeadline, 'Вы взялись');
      expect(r.pushBody, 'Вы и Bob взялись: Bring the ladder');
      expect(r.emailSentence, 'Вы и Bob взялись: Bring the ladder');
    });

    test('a hidden or blocked co-taker is never named', () async {
      final r = await deliver(
        _takenReceipt(),
        identity: _Identity(partnerHidden: true),
      );

      expect(r.pushBody, 'You took it: Bring the ladder');
      expect(r.emailSentence, 'You took it: Bring the ladder');
      expect('${r.pushBody}${r.emailSentence}', isNot(contains('Bob')));
    });

    test(
      'a co-taker with no name at all falls back to the solo sentence',
      () async {
        final r = await deliver(
          _takenReceipt(),
          identity: _Identity(partnerName: null),
        );

        expect(r.pushBody, 'You took it: Bring the ladder');
        expect(r.emailSentence, 'You took it: Bring the ladder');
      },
    );

    test('a co-taker without a name falls back to the solo sentence', () async {
      final r = await deliver(
        _takenReceipt(),
        identity: _Identity(partnerName: ''),
      );

      expect(r.pushBody, 'You took it: Bring the ladder');
      expect(r.emailSentence, 'You took it: Bring the ladder');
    });

    test('a solo receipt asks identity once and reads «You took it»', () async {
      final identity = _Identity();
      final r = await deliver(_takenReceipt(pair: false), identity: identity);

      expect(identity.requests.map((r) => r.actorId), [_taker]);
      expect(r.pushBody, 'You took it: Bring the ladder');
      expect(r.emailSentence, 'You took it: Bring the ladder');
    });
  });
}
