@Tags(['pg'])
library;

import 'package:characters/characters.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_channel_delivery_repository.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/notification_identity_repository.dart';
import 'package:tentura_server/data/repository/notification_outbox_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/data/repository/user_presence_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/service/beacon_notification_service.dart';
import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/data/service/email/templates/email_template_renderer.dart';
import 'package:tentura_server/data/service/email_notification_service.dart';
import 'package:tentura_server/data/service/fcm_batch_queue.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/entity/invite_accepted_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/mocks/invite_seed_prompt_repository_mock.dart';

const _author = 'Uemailtext001';
const _anna = 'Uemailtext002';
const _bob = 'Uemailtext003';
const _request = 'Bemailtext001';
const _post = 'Bemailtext002';
const _postRoot = 'Remailtext001';

const _longName = 'Annabelle-Montgomery-Featherston';
const _longTitle = 'Roof repair for the old red barn';

/// What the immediate email says, from the real dispatch of an event through
/// the delivery claim, the real notification service and the real email
/// service (identity read from Postgres at send time); only the SMTP sender
/// and the device transport are faked.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_IMMEDIATE_EMAIL_TEXT_TEST_DB',
    defaultNamePrefix: 'tentura_test_immediate_email_text',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late AttentionIntentCase intents;
  late TransactionalAttentionCase attention;
  late AttentionChannelDeliveryRepository deliveries;
  late _Sender sender;
  late DateTime nextClaimAt;
  FcmBatchQueue? queue;

  final env = Env(
    environment: Environment.test,
    publicOrigin: 'https://t.example',
    unsubscribeSigningSecret: 'secret',
    printEnv: false,
  );

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    deliveries = AttentionChannelDeliveryRepository(database);
    attention = TransactionalAttentionCase(
      MutatingUnitOfWork(database),
      AttentionDispatchRepository(database, Logger('ImmediateEmailText')),
    );
    intents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        BeaconRoomRepository(database),
        database,
        HelpOfferRepository(database),
        CommitmentRepository(database),
      ),
      UserRepository(
        Env(environment: 'test', printEnv: false),
        database,
        _NoopInviteGenealogyRepository(),
        InviteSeedPromptRepositoryMock(),
      ),
      BeaconAccessRepository(database),
      FakeUserBlockRepository(),
    );
  });

  setUp(() async {
    GetIt.I.pushNewScope(
      init: (scope) => scope.registerSingleton<Env>(env),
    );
    await _resetFixture(writer);
    sender = _Sender();
    nextClaimAt = DateTime.timestamp().add(const Duration(days: 1));
  });

  tearDown(() async {
    await GetIt.I.popScope();
    queue?.dispose();
    queue = null;
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  Future<void> record(AttentionDispatchIntent intent) => attention.runAction(
    actorUserId: intent.actorUserId,
    action: (transaction) => transaction.record(intent),
  );

  Future<void> setPreferences(
    String account, {
    String locale = 'en',
    int tzOffsetMinutes = 0,
    bool lockScreenSafe = false,
  }) => writer.execute(
    Sql.named(
      'INSERT INTO public.notification_preference '
      '(account_id, locale, tz_offset_minutes, lock_screen_safe) '
      'VALUES (@a, @l, @t, @s) '
      'ON CONFLICT (account_id) DO UPDATE SET locale = EXCLUDED.locale, '
      'tz_offset_minutes = EXCLUDED.tz_offset_minutes, '
      'lock_screen_safe = EXCLUDED.lock_screen_safe',
    ),
    parameters: {
      'a': account,
      'l': locale,
      't': tzOffsetMinutes,
      's': lockScreenSafe,
    },
  );

  Future<void> rename(String id, String name) => writer.execute(
    Sql.named('UPDATE public."user" SET display_name = @n WHERE id = @i'),
    parameters: {'n': name, 'i': id},
  );

  Future<void> retitle(String title) => writer.execute(
    Sql.named('UPDATE public.beacon SET title = @t WHERE id = @i'),
    parameters: {'t': title, 'i': _request},
  );

  Future<List<AttentionChannelDecision>> claim(String recipient) async {
    final claimed = <AttentionChannelDecision>[];
    for (var round = 0; round < 10; round++) {
      final jobs = await deliveries.claimDue(
        workerId: 'immediate-email-text-test',
        now: nextClaimAt.add(Duration(minutes: 5 * round)),
        limit: 50,
      );
      if (jobs.isEmpty) break;
      for (final job in jobs) {
        if (job.decision.recipientId == recipient) claimed.add(job.decision);
        await deliveries.markDelivered(
          id: job.id,
          workerId: 'immediate-email-text-test',
        );
      }
    }
    return claimed;
  }

  EmailNotificationService emailService() {
    final positional = <Object?>[
      NotificationPreferenceRepository(database),
      UserPresenceRepository(database),
      sender,
      _Contacts(),
      NotificationOutboxRepository(database),
      EmailLinkBuilder(env),
      env,
      Logger('ImmediateEmailText'),
    ];
    try {
      // The email service must read names and titles from the live identity,
      // wired like BeaconNotificationService: a named `identity` argument.
      return Function.apply(EmailNotificationService.new, positional, {
            #identity: NotificationIdentityRepository(database),
          })
          as EmailNotificationService;
    // Only the missing parameter is tolerated, nothing else.
    // ignore: avoid_catching_errors
    } on NoSuchMethodError {
      // No `identity` parameter yet: the service as it is today, so the
      // tests fail on the missing text behaviour rather than at load.
      return Function.apply(EmailNotificationService.new, positional)
          as EmailNotificationService;
    }
  }

  /// Hands [jobs] over and returns the immediate email the sender received.
  Future<RenderedEmail> deliverEmail(
    List<AttentionChannelDecision> jobs,
  ) async {
    expect(jobs, isNotEmpty, reason: 'the event produced a delivery job');
    final remote = _Remote();
    queue = FcmBatchQueue(remote, Logger('ImmediateEmailText'));
    final channels = BeaconNotificationService(
      queue!,
      _NoTokens(),
      remote,
      NotificationPreferenceRepository(database),
      emailService(),
      Logger('ImmediateEmailText'),
      identity: NotificationIdentityRepository(database),
    );
    await channels.handOffChannels(jobs);
    final deadline = DateTime.timestamp().add(const Duration(seconds: 8));
    while (sender.sent.isEmpty && DateTime.timestamp().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(sender.sent, hasLength(1), reason: 'one immediate email was sent');
    return sender.sent.single;
  }

  Future<List<AttentionChannelDecision>> acceptedOffer() async {
    await record(
      await intents.offerAccepted(
        receiverId: _bob,
        beaconId: _request,
        actorUserId: _anna,
        sourceEventKey: 'accepted:$_request:$_bob',
      ),
    );
    return claim(_bob);
  }

  Future<List<AttentionChannelDecision>> deadlineReminder() async {
    await record(
      await intents.deadlineReminder(
        beaconId: _request,
        participantUserIds: {_bob},
        deadline: DateTime.utc(2026, 11, 21, 17),
        sourceEventKey: 'reminder:$_request',
      ),
    );
    return claim(_bob);
  }

  Future<List<AttentionChannelDecision>> postShared({
    String note = 'Join us',
  }) async {
    await writer.execute(
      Sql.named(
        'INSERT INTO public.beacon_forward_edge '
        '(beacon_id, sender_id, recipient_id, note) '
        'VALUES (@b, @s, @r, @n)',
      ),
      parameters: {'b': _post, 's': _anna, 'r': _bob, 'n': note},
    );
    await record(
      await intents.relayReceived(
        beaconId: _post,
        senderId: _anna,
        beaconAuthorId: _author,
        recipientIds: const [_bob],
        sourceEventKey: 'relay:$_post:$_bob',
        beaconKind: BeaconKind.post,
        noteForRecipient: (_) => note,
      ),
    );
    return claim(_bob);
  }

  int graphemes(String text) => text.characters.length;

  group('an accepted offer email names the person and the Request', () {
    test('an English recipient gets the sentence and the Request in the '
        'subject', () async {
      final email = await deliverEmail(await acceptedOffer());
      expect(email.subject, 'Anna accepted your offer — «Fix the roof»');
    });

    test('a Russian recipient gets the renderer sentence, not the stored '
        'English text', () async {
      await setPreferences(_bob, locale: 'ru');
      final jobs = [
        for (final job in await acceptedOffer())
          job.copyWith(title: 'STORED-TITLE', body: 'STORED-BODY'),
      ];
      final email = await deliverEmail(jobs);
      expect(email.text, contains('Anna принял(а) ваше предложение'));
      for (final part in [email.subject, email.html, email.text]) {
        expect(part, isNot(contains('STORED')));
        expect(part, isNot(contains('accepted your offer')));
      }
    });

    test('a Russian recipient gets the same subject in Russian', () async {
      await setPreferences(_bob, locale: 'ru');
      final email = await deliverEmail(await acceptedOffer());
      expect(
        email.subject,
        'Anna принял(а) ваше предложение — «Fix the roof»',
      );
    });

    test('the body shows the Request as a link, then the sentence, then the '
        'call to action', () async {
      final email = await deliverEmail(await acceptedOffer());
      expect(
        email.html,
        matches(
          RegExp(
            r'<h2>\s*<a href="https://t\.example[^"]*">Fix the roof</a>\s*'
            r'</h2>\s*<p>Anna accepted your offer</p>',
          ),
        ),
      );
      expect(email.html, contains('Open in Tentura'));
      expect(email.text, contains('Fix the roof'));
      expect(email.text, contains('Anna accepted your offer'));
      expect(email.text, contains('Open in Tentura'));
      expect(email.text, contains('https://t.example'));
    });

    test('a Russian body has the localized call to action', () async {
      await setPreferences(_bob, locale: 'ru');
      final email = await deliverEmail(await acceptedOffer());
      expect(
        email.html,
        matches(
          RegExp(
            r'<h2>\s*<a href="https://t\.example[^"]*">Fix the roof</a>\s*'
            r'</h2>\s*<p>Anna принял\(а\) ваше предложение</p>',
          ),
        ),
      );
      expect(email.html, contains('Открыть в Tentura'));
      expect(email.text, contains('Fix the roof'));
      expect(email.text, contains('Anna принял(а) ваше предложение'));
      expect(email.text, contains('Открыть в Tentura'));
      expect(email.text, contains('https://t.example'));
    });

    test('stored job text never reaches the email', () async {
      final jobs = [
        for (final job in await acceptedOffer())
          job.copyWith(title: 'STORED-TITLE', body: 'STORED-BODY'),
      ];
      final email = await deliverEmail(jobs);
      expect(email.subject, 'Anna accepted your offer — «Fix the roof»');
      for (final part in [email.subject, email.html, email.text]) {
        expect(part, isNot(contains('STORED')));
      }
    });

    test(
      'a recipient who lost access gets a generic email naming nothing',
      () async {
        final jobs = await acceptedOffer();
        await writer.execute(
          Sql.named('DELETE FROM public.beacon_participant WHERE user_id = @u'),
          parameters: {'u': _bob},
        );
        final access = await writer.execute(
          Sql.named('SELECT public.beacon_can_read_content(@b, @u)'),
          parameters: {'b': _request, 'u': _bob},
        );
        expect(access.single[0], isFalse, reason: 'access really revoked');
        final email = await deliverEmail(jobs);
        expect(email.subject, 'Offer accepted');
        expect(email.html, contains('Anna accepted your offer'));
        expect(email.text, contains('Anna accepted your offer'));
        for (final part in [email.subject, email.html, email.text]) {
          expect(part, isNot(contains('Fix the roof')));
        }
      },
    );

    test('a Russian recipient who lost access gets the Russian generic '
        'subject', () async {
      await setPreferences(_bob, locale: 'ru');
      final jobs = await acceptedOffer();
      await writer.execute(
        Sql.named('DELETE FROM public.beacon_participant WHERE user_id = @u'),
        parameters: {'u': _bob},
      );
      final email = await deliverEmail(jobs);
      expect(email.subject, 'Предложение принято');
      expect(email.html, contains('Anna принял(а) ваше предложение'));
      expect(email.text, contains('Anna принял(а) ваше предложение'));
      for (final part in [email.subject, email.html, email.text]) {
        expect(part, isNot(contains('Fix the roof')));
      }
    });

    test(
      'lock-screen-safe recipients get the generic category subject',
      () async {
        await setPreferences(_bob, lockScreenSafe: true);
        final email = await deliverEmail(await acceptedOffer());
        expect(email.subject, 'Something needs your response');
        expect(email.subject, isNot(contains('Fix the roof')));
        expect(email.subject, isNot(contains('Anna')));
      },
    );

    test('lock-screen-safe Russian recipients get it in Russian', () async {
      await setPreferences(_bob, locale: 'ru', lockScreenSafe: true);
      final email = await deliverEmail(await acceptedOffer());
      expect(email.subject, 'Нужен ваш ответ');
      expect(email.subject, isNot(contains('Fix the roof')));
      expect(email.subject, isNot(contains('Anna')));
    });
  });

  group('a deadline reminder email gives the date in the recipient time', () {
    test('English subject has the local date and the Request', () async {
      await setPreferences(_bob, tzOffsetMinutes: 60);
      final email = await deliverEmail(await deadlineReminder());
      expect(email.subject, 'Deadline: 21 Nov, 18:00 — «Fix the roof»');
      for (final part in [email.subject, email.html, email.text]) {
        expect(part, isNot(contains('2026-11-21')));
        expect(part, isNot(contains('T17:00')));
      }
    });

    test('Russian subject has the Russian month', () async {
      await setPreferences(_bob, locale: 'ru', tzOffsetMinutes: 60);
      final email = await deliverEmail(await deadlineReminder());
      expect(email.subject, 'Срок: 21 ноября, 18:00 — «Fix the roof»');
      for (final part in [email.subject, email.html, email.text]) {
        expect(part, isNot(contains('2026-11-21')));
        expect(part, isNot(contains('T17:00')));
      }
    });

    for (final (locale, prefix) in [
      ('en', 'Deadline: 21 Nov, 18:00 — «'),
      ('ru', 'Срок: 21 ноября, 18:00 — «'),
    ]) {
      test('a long Request title and a long person name keep the subject '
          'within the cap with a complete quoted label ($locale)', () async {
        await rename(_anna, _longName);
        await retitle(_longTitle);
        await setPreferences(_bob, locale: locale, tzOffsetMinutes: 60);
        expect(graphemes(_longName), 32);
        expect(graphemes(_longTitle), 32);
        final email = await deliverEmail(await deadlineReminder());
        expect(graphemes(email.subject), lessThanOrEqualTo(78));
        expect(email.subject, startsWith(prefix));
        final label = RegExp(r'«([^»]*)»$').firstMatch(email.subject);
        expect(label, isNotNull, reason: 'ends with a complete «label»');
        expect(graphemes(label!.group(1)!), greaterThanOrEqualTo(16));
        expect(email.subject, isNot(contains('T17:00')));
      });
    }
  });

  group('a deadline reminder subject cuts an overlong Request title', () {
    test('the label is cut inside the quotes and the cap holds', () async {
      await retitle(
        'Roof repair for the old red barn and the whole stable '
        'yard before the first heavy autumn rain arrives',
      );
      await setPreferences(_bob, tzOffsetMinutes: 60);
      final email = await deliverEmail(await deadlineReminder());
      expect(graphemes(email.subject), lessThanOrEqualTo(78));
      expect(email.subject, startsWith('Deadline: 21 Nov, 18:00 — «'));
      expect(email.subject, endsWith('…»'));
    });
  });

  group('an invite-accepted email keeps its stored-text localization', () {
    test('a Russian recipient gets the Russian connection text', () async {
      await setPreferences(_bob, locale: 'ru');
      final sentEmail = await emailService().considerImmediateByCategory(
        recipientUserId: _bob,
        channelCollapseKey: 'invite-accepted:$_bob',
        title: 'Anna · @anna',
        body: 'You are now connected on Tentura.',
        actionUrl: '/#/profile/view/$_anna',
        categoryScope: 'connections',
      );
      expect(sentEmail, isTrue);
      final email = sender.sent.single;
      expect(email.text, contains('Вы теперь связаны в Tentura.'));
      expect(email.text, isNot(contains('You are now connected')));
    });
  });

  group('connection emails about unavailable Requests', () {
    test(
      'Russian recipients get a localized invitation acceptance email',
      () async {
        await setPreferences(_bob, locale: 'ru');
        final intent = await intents.inviteAccepted(
          notification: const InviteAcceptedNotificationIntent(
            inviterUserId: _bob,
            accepterUserId: _anna,
            accepterDisplayName: 'Anna',
            accepterHandle: 'anna',
            actionUrl: '/#/profile/view/$_anna',
            inviteOrigin: 'existing_account',
          ),
          sourceEventKey: 'invite-accepted:$_bob',
          lapsedRequestTitle: 'Fix the roof',
        );
        final sent = await emailService().considerImmediateByCategory(
          recipientUserId: intent.recipients.single.recipientId,
          channelCollapseKey: intent.collapseKey,
          title: intent.title,
          body: intent.body,
          actionUrl: intent.actionUrl,
          categoryScope: 'connections',
        );
        expect(sent, isTrue);
        const expectedBody =
            'Уже был аккаунт в Tentura. Теперь вы связаны. '
            'Запрос «Fix the roof» больше недоступен по этому приглашению.';
        expect(sender.itemBodies, [expectedBody]);
      },
    );

    test('Russian recipients get a localized connection email when the '
        'actor has no display name and no rendered copy is supplied', () async {
      await setPreferences(_bob, locale: 'ru');
      await rename(_anna, '');
      final intent = await intents.mutualConnectionFormed(
        actorUserId: _anna,
        counterpartUserId: _bob,
        sourceEventKey: 'connection:$_anna:$_bob',
        lapsedRequestTitle: 'Fix the roof',
      );
      expect(intent.kind, NotificationKind.inviteAccepted);
      await emailService().considerImmediate(
        recipientUserId: intent.recipients.single.recipientId,
        kind: intent.kind,
        beaconId: intent.beaconId ?? '',
        channelCollapseKey: intent.collapseKey,
        title: intent.title,
        body: intent.body,
        actionUrl: intent.actionUrl,
        pushDelivered: false,
      );
      const expectedBody =
          'Вы теперь связаны в Tentura. '
          'Запрос «Fix the roof» больше недоступен по этому приглашению.';
      expect(sender.itemBodies, [expectedBody]);
    });
  });

  group(
    'immediate connection emails name the inviter in the recipient locale',
    () {
      const requestTitle = 'Fix the roof';
      const russianConnection = 'Вы и Anna теперь на связи.';
      const russianWithRequest =
          '$russianConnection Запрос «Fix the roof» больше недоступен '
          'по этому приглашению.';

      Future<AttentionChannelDecision> connectionDelivery({
        required String locale,
        String counterpart = _bob,
        String? lapsedRequestTitle,
      }) async {
        await setPreferences(counterpart, locale: locale);
        final intent = await intents.mutualConnectionFormed(
          actorUserId: _anna,
          counterpartUserId: counterpart,
          sourceEventKey: 'connection:$_anna:$counterpart',
          lapsedRequestTitle: lapsedRequestTitle,
        );
        await record(intent);
        return (await claim(counterpart)).single;
      }

      Future<void> sendConnection(AttentionChannelDecision decision) async {
        expect(decision.kind, NotificationKind.inviteAccepted);
        await emailService().considerImmediate(
          recipientUserId: decision.recipientId,
          kind: decision.kind,
          beaconId: decision.beaconId ?? '',
          channelCollapseKey: decision.dedupKey,
          title: decision.title,
          // Pass the stored body and leave rendered copy unset.
          body: decision.body,
          actionUrl: decision.actionUrl,
          pushDelivered: false,
        );
      }

      test('the connection and unavailable Request are stated in English and '
          'Russian for the respective recipients', () async {
        const englishBody =
            'You and Anna are now connected. The Request «Fix the roof» is '
            'no longer available through this invitation.';
        await sendConnection(
          await connectionDelivery(
            locale: 'en',
            counterpart: _author,
            lapsedRequestTitle: requestTitle,
          ),
        );
        expect(sender.itemBodies, [englishBody]);

        await sendConnection(
          await connectionDelivery(
            locale: 'ru',
            lapsedRequestTitle: requestTitle,
          ),
        );
        expect(sender.itemBodies, [englishBody, russianWithRequest]);
      });

      for (final (description, name) in [
        ('the connection sentence is localized in English and Russian', 'Anna'),
        ('both locales trim spaces around the inviter name', '  Anna  '),
      ]) {
        test('$description when there is no unavailable Request', () async {
          await rename(_anna, name);
          const englishBody = 'You and Anna are now connected.';
          await sendConnection(
            await connectionDelivery(
              locale: 'en',
              counterpart: _author,
            ),
          );
          expect(sender.itemBodies, [englishBody]);

          await sendConnection(await connectionDelivery(locale: 'ru'));
          expect(sender.itemBodies, [englishBody, russianConnection]);
        });
      }

      test('the connections category sends one email with the Russian '
          'connection and unavailable Request text', () async {
        final decision = await connectionDelivery(
          locale: 'ru',
          lapsedRequestTitle: requestTitle,
        );
        final sent = await emailService().considerImmediateByCategory(
          recipientUserId: decision.recipientId,
          channelCollapseKey: decision.dedupKey,
          title: decision.title,
          body: decision.body,
          actionUrl: decision.actionUrl,
          categoryScope: 'connections',
        );
        expect(sent, isTrue);
        expect(sender.itemBodies, [russianWithRequest]);
      });

      test('ru-RU recipients get the Russian connection and unavailable '
          'Request text', () async {
        await sendConnection(
          await connectionDelivery(
            locale: 'ru-RU',
            lapsedRequestTitle: requestTitle,
          ),
        );
        expect(sender.itemBodies, [russianWithRequest]);
      });

      test(
        'the Russian connection email preserves a Cyrillic inviter name',
        () async {
          await rename(_anna, 'Анна Иванова');
          await sendConnection(await connectionDelivery(locale: 'ru'));
          expect(sender.itemBodies, ['Вы и Анна Иванова теперь на связи.']);
        },
      );

      test('the Russian email preserves a name containing “The Request” and '
          'names the unavailable Request separately', () async {
        await rename(_anna, 'Max The Request');
        await sendConnection(
          await connectionDelivery(
            locale: 'ru',
            lapsedRequestTitle: requestTitle,
          ),
        );
        const expectedBody =
            'Вы и Max The Request теперь на связи. '
            'Запрос «Fix the roof» больше недоступен по этому приглашению.';
        expect(sender.itemBodies, [expectedBody]);
      });
    },
  );

  group('a Post share email names the sharer and the Post', () {
    test(
      'English subject has the sentence and the unquoted Post label',
      () async {
        final email = await deliverEmail(await postShared());
        expect(
          email.subject,
          'Anna shared a post with you — Post: Walk in the park',
        );
        expect(email.subject, isNot(contains('«')));
        expect(graphemes(email.subject), lessThanOrEqualTo(78));
      },
    );

    test('Russian subject is localized', () async {
      await setPreferences(_bob, locale: 'ru');
      final email = await deliverEmail(await postShared());
      expect(
        email.subject,
        'Anna делится с вами постом — Пост: Walk in the park',
      );
      expect(email.subject, isNot(contains('«')));
    });

    test('the sender note shows as an escaped excerpt in the body, not in '
        'the subject', () async {
      final email = await deliverEmail(await postShared(note: 'Join us <now>'));
      expect(email.html, contains('Join us &lt;now&gt;'));
      expect(email.text, contains('Join us <now>'));
      expect(
        email.subject,
        'Anna shared a post with you — Post: Walk in the park',
      );
    });
  });

  group('the subject never exceeds 78 characters', () {
    test('English: the label is cut first, inside the quotes, and the '
        'sentence stays whole', () async {
      await rename(_anna, _longName);
      await retitle(_longTitle);
      expect(graphemes(_longName), 32);
      expect(graphemes(_longTitle), 32);
      final email = await deliverEmail(await acceptedOffer());
      expect(graphemes(email.subject), lessThanOrEqualTo(78));
      expect(email.subject, startsWith('$_longName accepted your offer — «'));
      expect(email.subject, endsWith('…»'));
    });

    test('Russian: the sentence is shortened after the label reaches its '
        'minimum', () async {
      await rename(_anna, _longName);
      await retitle(_longTitle);
      await setPreferences(_bob, locale: 'ru');
      final email = await deliverEmail(await acceptedOffer());
      expect(graphemes(email.subject), lessThanOrEqualTo(78));
      final parts = email.subject.split(' — «');
      expect(parts, hasLength(2));
      expect(parts.first, endsWith('…'), reason: 'the sentence was shortened');
      expect(parts.first, startsWith(_longName));
      final label = parts.last;
      expect(label, endsWith('…»'));
      expect(
        graphemes(label.substring(0, label.length - 1)),
        greaterThanOrEqualTo(16),
        reason: 'the quoted label keeps 16+ graphemes, ellipsis included',
      );
    });
  });
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.notification_preference,
  public.user_block,
  public.beacon_forward_edge,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_participant,
  public.beacon_room_message,
  public.beacon,
  public."user"
CASCADE
''');
  for (final (id, name) in [
    (_author, 'Owner'),
    (_anna, 'Anna'),
    (_bob, 'Bob'),
  ]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$name', 'key-$id')
''');
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at, end_at,
   is_discoverable)
VALUES ('$_request', '$_author', 'Fix the roof', '', 0, 0, now(),
  now() + interval '3 days', false)
''');
  await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pemailtext001', '$_request', '$_bob', 0, 0, 3)
''');
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   published_at, is_discoverable)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, now(), false)
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_postRoot', '$_post', '$_author', 'Walk in the park')
''');
  await writer.execute('''
UPDATE public.beacon SET post_root_message_id = '$_postRoot'
WHERE id = '$_post'
''');
}

final class _Sender extends Fake implements EmailSenderPort {
  final sent = <RenderedEmail>[];
  final itemBodies = <String>[];

  @override
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  }) async {
    itemBodies.add(content.item.body);
    sent.add(
      const EmailTemplateRenderer().renderNotification(
        content: content,
        locale: locale,
      ),
    );
  }
}

final class _Contacts extends Fake implements VerifiedContactRepositoryPort {
  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async =>
      '$accountId@example.com';
}

final class _Remote implements FcmRemoteRepositoryPort {
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

/// No device tokens: the push is not delivered, so the email goes out at once.
final class _NoTokens extends Fake implements FcmTokenRepositoryPort {
  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async =>
      const [];
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
