@Tags(['pg'])
library;

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/repository/attention_channel_delivery_repository.dart';
import 'package:tentura_server/data/repository/fcm_token_repository.dart';
import 'package:tentura_server/data/repository/notification_identity_repository.dart';
import 'package:tentura_server/data/repository/notification_outbox_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_presence_repository.dart';
import 'package:tentura_server/data/service/beacon_notification_service.dart';
import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/data/service/email/templates/email_template_renderer.dart';
import 'package:tentura_server/data/service/email_notification_service.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/fcm_batch_queue_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_channel_delivery_case.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/post_bud_privacy_fixture.dart';

const _anna = PostBudPrivacyFixture.anna;
const _bob = PostBudPrivacyFixture.bob;
const _carol = PostBudPrivacyFixture.carol;
const _post = PostBudPrivacyFixture.post;
const _title = PostBudPrivacyFixture.title;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_NOTIFICATION_PRIVACY_TEST_DB',
    defaultNamePrefix: 'tentura_test_bud_notify_privacy',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late PostBudPrivacyFixture fixture;
  late NotificationIdentityRepository identity;
  late NotificationOutboxRepository outbox;
  late NotificationPreferenceRepository preferences;
  late String child;
  final contacts = _Contacts();
  final env = Env(
    environment: Environment.test,
    printEnv: false,
    publicOrigin: 'https://tentura.example',
    unsubscribeSigningSecret: 'bud-privacy-test',
    emailDigestHour: 8,
  );

  setUpAll(() => GetIt.I.registerSingleton<Env>(env));
  tearDownAll(() => GetIt.I.unregister<Env>());

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    final database = openDisposablePgDatabase(target);
    addTearDown(
      () => tearDownDisposablePgWriter(session: session, drift: database),
    );
    fixture = PostBudPrivacyFixture(
      session.writer,
      database,
      target.databaseEnv,
    );
    identity = NotificationIdentityRepository(database);
    outbox = NotificationOutboxRepository(database);
    preferences = NotificationPreferenceRepository(database);
  });

  setUp(() async {
    await fixture.reset();
    await fixture.seedPost();
    child = await fixture.bud();

    // Carol was never ticked in the bud dialog. She later joins the Request
    // as a helper. Schedule a reminder while she is a member and remove her
    // admission before either delivery worker runs.
    for (final member in [_bob, _carol]) {
      await fixture.writer.execute('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES ('$child', '$member', 0, 0, 3)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET room_access = 3
''');
      expect(await fixture.canRead(child, member), isTrue);
    }
    final deadline = DateTime.timestamp().add(const Duration(days: 1));
    final reminder = await fixture.intents.deadlineReminder(
      beaconId: child,
      participantUserIds: {_bob, _carol},
      deadline: deadline,
      sourceEventKey: 'garden-request-deadline',
    );
    await fixture.attention.run(
      actorUserId: _anna,
      intent: reminder,
      mutation: () async {},
    );
    for (final member in [_bob, _carol]) {
      expect(
        (await outbox.pendingForAccount(member))
            .where((item) => item.kind == NotificationKind.deadlineReminder)
            .single
            .actionUrl,
        contains(child),
        reason:
            'A reminder was queued while this recipient could read the Request',
      );
    }
    await fixture.writer.execute('''
DELETE FROM public.beacon_participant WHERE beacon_id = '$child' AND user_id = '$_carol'
''');
  });

  Future<void> expectDeliveryIdentity() async {
    expect(await fixture.canRead(_post, _carol), isTrue);
    expect(await fixture.canRead(child, _carol), isFalse);
    final requests = [
      IdentityRequest(beaconId: child),
      IdentityRequest(beaconId: _post, relatedBeaconId: child),
    ];
    final bob = await identity.resolve(_bob, requests);
    expect(bob[0].readable, isTrue);
    expect(bob[0].label, _title);
    expect(bob[1].relatedLabel, _title);
    final carol = await identity.resolve(_carol, requests);
    expect(carol[0].readable, isFalse);
    expect(carol[0].label, isNull);
    expect(carol[1].readable, isTrue);
    expect(carol[1].relatedLabel, isNull);
  }

  for (final (description, transition) in [
    (
      'while the Post and Request are open',
      (PostBudPrivacyFixture fixture, String child) async {},
    ),
    (
      'after the Request closes',
      (PostBudPrivacyFixture fixture, String child) =>
          fixture.closeRequest(child),
    ),
    (
      'after the Post closes',
      (PostBudPrivacyFixture fixture, String child) => fixture.uow.run(
        actorUserId: _anna,
        action: () async {
          await PostLockRepository(fixture.database).lockForPostMutation(_post);
          await fixture.postClose.closeByAuthor(postId: _post, actorId: _anna);
        },
      ),
    ),
  ]) {
    test('the digest omits an unreadable Request $description', () async {
      await transition(fixture, child);
      await expectDeliveryIdentity();
      final mail = _CapturedMail();
      await EmailDigestCase(
        preferences,
        outbox,
        contacts,
        mail,
        EmailLinkBuilder(env),
        env,
        Logger('PostBudDigestPrivacy'),
        identity: identity,
      ).runDue(now: DateTime.timestamp().copyWith(hour: env.emailDigestHour));

      final bob = mail.digests[_bob]!.single;
      for (final mimeBody in [bob.html, bob.text]) {
        expect(mimeBody, allOf(contains(child), contains(_title)));
      }
      expect(_emailContents(mail.digests[_carol]), _omitsRequest(child));
    });
  }

  test(
    'queued push and immediate email omit a Request the recipient cannot read',
    () async {
      await expectDeliveryIdentity();
      final mail = _CapturedMail();
      final push = _CapturedPush();
      final tokens = FcmTokenRepository(fixture.database);
      for (final recipient in [_bob, _carol]) {
        await tokens.putToken(
          userId: recipient,
          appId: '00000000-0000-4000-8000-000000000001',
          token: 'token-for-$recipient',
          platform: 'web',
        );
      }
      final logger = Logger('PostBudChannelPrivacy');
      final immediate = _AwaitedEmail(
        preferences,
        UserPresenceRepository(fixture.database),
        mail,
        contacts,
        outbox,
        EmailLinkBuilder(env),
        env,
        logger,
      );
      final worker = AttentionChannelDeliveryCase(
        AttentionChannelDeliveryRepository(fixture.database),
        BeaconNotificationService(
          push,
          tokens,
          _UnusedFcm(),
          preferences,
          immediate,
          logger,
          identity: identity,
        ),
      );
      final now = DateTime.timestamp();
      await worker.runDue(workerId: 'delivery-worker', now: now);
      // Bob may also have a queued invitation, and the worker sends at most
      // one event per account per pass.
      await worker.runDue(
        workerId: 'delivery-worker',
        now: now.add(const Duration(minutes: 2)),
      );
      await Future.wait(immediate.pending).timeout(const Duration(seconds: 5));

      String reminders(String recipient) => [
        for (final message
            in push.messages[recipient] ?? <FcmNotificationEntity>[])
          if (message.kind == NotificationKind.deadlineReminder)
            '${message.title}\n${message.body}\n${message.actionUrl}\n${message.beaconId}',
      ].join('\n');

      expect(reminders(_bob), allOf(contains(child), contains(_title)));
      expect(
        _emailContents(mail.immediate[_bob]),
        allOf(contains(child), contains(_title)),
      );
      expect(
        {
          'Carol push': reminders(_carol),
          'Carol immediate email': _emailContents(mail.immediate[_carol]),
        },
        {
          'Carol push': _omitsRequest(child),
          'Carol immediate email': _omitsRequest(child),
        },
      );
    },
  );
}

Matcher _omitsRequest(String child) =>
    allOf(isNot(contains(child)), isNot(contains(_title)));

String _emailContents(List<RenderedEmail>? messages) => [
  for (final email in messages ?? <RenderedEmail>[]) ...[
    email.subject,
    email.html,
    email.text,
  ],
].join('\n');

final class _Contacts extends Fake implements VerifiedContactRepositoryPort {
  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async =>
      '$accountId@example.com';
}

final class _CapturedMail extends Fake implements EmailSenderPort {
  final digests = <String, List<RenderedEmail>>{};
  final immediate = <String, List<RenderedEmail>>{};

  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {
    (digests[to.split('@').first] ??= []).add(
      const EmailTemplateRenderer().renderDigest(
        content: content,
        locale: locale,
      ),
    );
  }

  @override
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  }) async {
    (immediate[to.split('@').first] ??= []).add(
      const EmailTemplateRenderer().renderNotification(
        content: content,
        locale: locale,
      ),
    );
  }
}

final class _CapturedPush extends Fake implements FcmBatchQueuePort {
  final messages = <String, List<FcmNotificationEntity>>{};

  @override
  void enqueue({
    required String receiverId,
    required Set<String> fcmTokens,
    required FcmNotificationEntity message,
  }) {
    (messages[receiverId] ??= []).add(message);
  }
}

final class _UnusedFcm extends Fake implements FcmRemoteRepositoryPort {}

/// Wait for the production mail service through its asynchronous handoff.
final class _AwaitedEmail extends EmailNotificationService {
  _AwaitedEmail(
    super._preferences,
    super._presence,
    super._email,
    super._contacts,
    super._outbox,
    super._links,
    super._env,
    super._logger,
  );

  final pending = <Future<void>>[];

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
  }) {
    final delivery = super.considerImmediate(
      recipientUserId: recipientUserId,
      kind: kind,
      beaconId: beaconId,
      channelCollapseKey: channelCollapseKey,
      title: title,
      body: body,
      actionUrl: actionUrl,
      pushDelivered: pushDelivered,
      copy: copy,
    );
    pending.add(delivery);
    return delivery;
  }
}
