@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_channel_delivery_repository.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_plan_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/notification_identity_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/service/beacon_notification_service.dart';
import 'package:tentura_server/data/service/fcm_batch_queue.dart';
import 'package:tentura_server/data/service/push_action_token_service.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_user_block_repository.dart';

const _author = 'Upushtext0001';
const _anna = 'Upushtext0002';
const _bob = 'Upushtext0003';
const _request = 'Bpushtext0001';

/// What a pushed notification says, from the real dispatch of an event through
/// the delivery claim, the real notification service (identity read from
/// Postgres at send time) and the real FCM batch queue; only the device
/// transport is faked.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PUSH_TEXT_FROM_IDENTITY_TEST_DB',
    defaultNamePrefix: 'tentura_test_push_text_identity',
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
  late _Remote remote;
  late _Email email;
  late DateTime nextClaimAt;
  FcmBatchQueue? queue;

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
      AttentionDispatchRepository(database, Logger('PushTextIdentity')),
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
    await _resetFixture(writer);
    remote = _Remote();
    email = _Email();
    nextClaimAt = DateTime.timestamp().add(const Duration(days: 1));
  });

  tearDown(() {
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

  Future<void> setLocale(String account, String locale) => writer.execute(
    Sql.named(
      'INSERT INTO public.notification_preference (account_id, locale) '
      'VALUES (@a, @l) '
      'ON CONFLICT (account_id) DO UPDATE SET locale = EXCLUDED.locale',
    ),
    parameters: {'a': account, 'l': locale},
  );

  Future<void> offerHelp({String note = 'I have a ladder'}) async => record(
    await intents.helpOfferSubmitted(
      beaconId: _request,
      helpOffererId: _anna,
      authorId: _author,
      sourceEventKey: 'offer:$_request:$_anna',
      message: note,
    ),
  );

  Future<List<AttentionChannelDecision>> claim(String recipient) async {
    final claimed = <AttentionChannelDecision>[];
    for (var round = 0; round < 10; round++) {
      final jobs = await deliveries.claimDue(
        workerId: 'push-text-identity-test',
        now: nextClaimAt.add(Duration(minutes: 5 * round)),
        limit: 50,
      );
      if (jobs.isEmpty) break;
      for (final job in jobs) {
        if (job.decision.recipientId == recipient) claimed.add(job.decision);
        await deliveries.markDelivered(
          id: job.id,
          workerId: 'push-text-identity-test',
        );
      }
    }
    return claimed;
  }

  BeaconNotificationService service() {
    final logger = Logger('PushTextIdentity');
    queue = FcmBatchQueue(remote, logger);
    return BeaconNotificationService(
      queue!,
      _Tokens(),
      remote,
      NotificationPreferenceRepository(database),
      email,
      logger,
      identity: NotificationIdentityRepository(database),
      pushActionTokens: PushActionTokenService(Env()),
      planRepository: BeaconPlanRepository(database),
    );
  }

  /// Hands [jobs] over and returns what the device transport received.
  Future<List<FcmNotificationEntity>> deliver(
    List<AttentionChannelDecision> jobs, {
    Duration settle = const Duration(milliseconds: 2500),
  }) async {
    await service().handOffChannels(jobs);
    final deadline = DateTime.timestamp().add(settle);
    while (remote.sent.isEmpty && DateTime.timestamp().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return remote.sent;
  }

  group('push text is built at send time from the live identity', () {
    test('an English author is told who offered help, under the Request title',
        () async {
      await offerHelp();
      final sent = await deliver(await claim(_author));
      expect(sent, hasLength(1));
      expect(sent.single.title, 'Fix the roof');
      expect(sent.single.body, 'Anna offered help: I have a ladder');
    });

    test('a Russian author gets the same push in Russian', () async {
      await setLocale(_author, 'ru');
      await offerHelp();
      final sent = await deliver(await claim(_author));
      expect(sent, hasLength(1));
      expect(sent.single.title, 'Fix the roof');
      expect(sent.single.body, 'Anna предлагает помощь: I have a ladder');
    });

    test('a name changed after the event shows in the push', () async {
      await offerHelp();
      final jobs = await claim(_author);
      await writer.execute(
        Sql.named('UPDATE public."user" SET display_name = @n WHERE id = @i'),
        parameters: {'n': 'Anna K', 'i': _anna},
      );
      final sent = await deliver(jobs);
      expect(sent, hasLength(1));
      expect(sent.single.body, startsWith('Anna K offered help'));
    });

    test('stored job text never reaches the device', () async {
      await offerHelp();
      final jobs = [
        for (final job in await claim(_author))
          job.copyWith(title: 'STORED-TITLE', body: 'STORED-BODY'),
      ];
      final sent = await deliver(jobs);
      expect(sent, hasLength(1));
      expect(sent.single.title, 'Fix the roof');
      expect(sent.single.body, 'Anna offered help: I have a ladder');
      final m = sent.single;
      final everything = [
        m.title,
        m.body,
        m.imageUrl,
        m.actionUrl,
        m.beaconId,
        m.coordinationItemId,
        m.tag,
        m.actionToken,
        m.actionFeedback,
        for (final a in m.actions) '${a.id} ${a.title}',
      ].join('\n');
      expect(everything, isNot(contains('STORED')));
    });

    Future<List<AttentionChannelDecision>> relayToBob() async {
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon_forward_edge '
          '(beacon_id, sender_id, recipient_id) VALUES (@b, @s, @r)',
        ),
        parameters: {'b': _request, 's': _anna, 'r': _bob},
      );
      await record(
        await intents.relayReceived(
          beaconId: _request,
          senderId: _anna,
          beaconAuthorId: _author,
          recipientIds: const [_bob],
          sourceEventKey: 'relay:$_request:$_bob',
          noteForRecipient: (_) => 'Please look at the gutter',
        ),
      );
      final jobs = await claim(_bob);
      expect(jobs, isNotEmpty);
      return jobs;
    }

    Future<bool> bobCanRead() async {
      final rows = await writer.execute(
        Sql.named('SELECT public.beacon_can_read_content(@b, @u)'),
        parameters: {'b': _request, 'u': _bob},
      );
      return rows.single[0]! as bool;
    }

    test('a forwarded recipient who can read the Request sees its title',
        () async {
      final jobs = await relayToBob();
      expect(await bobCanRead(), isTrue);
      final sent = await deliver(jobs);
      expect(sent, hasLength(1));
      expect(sent.single.title, 'Fix the roof');
      expect(sent.single.body, contains('Anna'));
    });

    test('a recipient who lost access gets a generic push naming nothing',
        () async {
      final jobs = await relayToBob();
      await writer.execute(
        Sql.named(
          'DELETE FROM public.beacon_forward_edge WHERE recipient_id = @r',
        ),
        parameters: {'r': _bob},
      );
      await writer.execute(
        Sql.named('DELETE FROM public.beacon_participant WHERE user_id = @r'),
        parameters: {'r': _bob},
      );
      expect(await bobCanRead(), isFalse, reason: 'access really revoked');
      final sent = await deliver(jobs);
      expect(sent, hasLength(1));
      expect(sent.single.title, 'Request forwarded');
      expect(sent.single.body, 'Anna forwarded you a request');
      for (final text in [sent.single.title, sent.single.body]) {
        expect(text, isNot(contains('Fix the roof')));
        expect(text, isNot(contains('gutter')));
      }
    });

    test('a lock-screen-safe Russian recipient gets localized generic text',
        () async {
      await writer.execute(
        Sql.named(
          'INSERT INTO public.notification_preference '
          '(account_id, locale, lock_screen_safe) VALUES (@a, @l, true)',
        ),
        parameters: {'a': _author, 'l': 'ru'},
      );
      await offerHelp();
      final sent = await deliver(await claim(_author));
      final expected = const NotificationCopyRenderer().lockScreenSafe(
        categoryOf(NotificationKind.commitmentEvent),
        'ru',
      );
      expect(sent, hasLength(1));
      expect(sent.single.title, 'Tentura');
      expect(sent.single.body, expected.body);
      expect(sent.single.body, matches(RegExp('[А-Яа-я]')));
      for (final text in [sent.single.title, sent.single.body]) {
        expect(text, isNot(contains('Fix the roof')));
        expect(text, isNot(contains('Anna')));
        expect(text, isNot(contains('ladder')));
      }
    });

    test('a plan step push goes out directly with its rendered text',
        () async {
      await record(
        await intents.planEvent(
          eventType: AttentionEventType.planStepDue,
          beaconId: _request,
          beaconTitle: 'Fix the roof',
          actorUserId: null,
          recipients: {_bob: AttentionRecipientReason.planStepAssignee},
          sourceEventKey: 'plan:due:S1',
          stepId: 'S1',
          stepTitle: 'Bring tools',
        ),
      );
      final sent = await deliver(await claim(_bob));
      expect(sent, hasLength(1));
      expect(sent.single.title, 'Fix the roof');
      expect(sent.single.body, 'Your step «Bring tools» has started');
      expect(sent.single.tag, 'plan:S1');
      expect(sent.single.stepId, 'S1');
      expect(sent.single.actions, isNotEmpty, reason: 'plan buttons kept');
      expect(sent.single.actionToken, isNotNull);
    });
  });

  group('pushes about one Request collapse under its title', () {
    test('two offers from different people give one push titled with the '
        'Request and counting both', () async {
      await offerHelp();
      await record(
        await intents.helpOfferSubmitted(
          beaconId: _request,
          helpOffererId: _bob,
          authorId: _author,
          sourceEventKey: 'offer:$_request:$_bob',
          message: 'I have a car',
        ),
      );
      final jobs = await claim(_author);
      expect(jobs, hasLength(2));
      final sent = await deliver(jobs);
      expect(sent, hasLength(1));
      expect(sent.single.title, 'Fix the roof');
      expect(sent.single.body, contains('2'));
    });
  });

  group('a blocked pair gets no push and no immediate email', () {
    Future<void> block(String blocker, String blocked) => writer.execute(
      Sql.named(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        'VALUES (@x, @y, @x)',
      ),
      parameters: {'x': blocker, 'y': blocked},
    );

    test('control: without a block the same job pushes and tries email',
        () async {
      await offerHelp();
      final jobs = await claim(_author);
      expect(jobs, isNotEmpty);
      final sent = await deliver(jobs);
      expect(sent, hasLength(1));
      expect(email.calls, greaterThan(0));
    });

    test('the recipient blocked the actor before hand-off', () async {
      await offerHelp();
      final jobs = await claim(_author);
      expect(jobs, isNotEmpty);
      await block(_author, _anna);
      final sent = await deliver(jobs);
      expect(sent, isEmpty);
      expect(email.calls, 0);
    });

    test('the actor blocked the recipient before hand-off', () async {
      await offerHelp();
      final jobs = await claim(_author);
      expect(jobs, isNotEmpty);
      await block(_anna, _author);
      final sent = await deliver(jobs);
      expect(sent, isEmpty);
      expect(email.calls, 0);
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
VALUES ('Ppushtext001', '$_request', '$_bob', 0, 0, 3)
''');
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

final class _Tokens extends Fake implements FcmTokenRepositoryPort {
  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async => [
    FcmTokenEntity(
      userId: userId,
      appId: UuidValue.fromString('00000000-0000-4000-8000-000000000001'),
      platform: 'web',
      token: 'token-$userId',
      createdAt: DateTime.utc(2026),
      lastRefreshedAt: DateTime.utc(2026),
    ),
  ];
}

final class _Email extends Fake implements EmailNotificationPort {
  int calls = 0;

  @override
  Future<bool> considerImmediate({
    required String recipientUserId,
    required NotificationKind kind,
    required String beaconId,
    required String channelCollapseKey,
    required String title,
    required String body,
    required String actionUrl,
    required bool pushDelivered,
  }) async {
    calls++;
    return false;
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
    calls++;
    return false;
  }
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
