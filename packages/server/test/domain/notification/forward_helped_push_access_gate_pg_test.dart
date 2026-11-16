@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_plan_repository.dart';
import 'package:tentura_server/data/repository/notification_identity_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/data/service/beacon_notification_service.dart';
import 'package:tentura_server/data/service/fcm_batch_queue.dart';
import 'package:tentura_server/data/service/push_action_token_service.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/entity/forward_helped_content.dart';
import 'package:tentura_server/domain/entity/help_path_node.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

const _author = 'Ufhgate00001';
const _forwarder = 'Ufhgate00002';
const _request = 'Bfhgate00001';
const _liveTitle = 'Fix the roof';
const _staleTitle = 'Old frozen title';

/// What the forward-helped push and its immediate email say to a forwarder,
/// from the real notification service reading access and the Request title
/// from Postgres at hand-off; only the device transport and SMTP are faked.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_HELPED_PUSH_GATE_TEST_DB',
    defaultNamePrefix: 'tentura_test_fh_push_gate',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late _Remote remote;
  late _Email email;
  FcmBatchQueue? queue;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    database = openDisposablePgDatabase(target);
  });

  setUp(() async {
    await _resetFixture(writer);
    remote = _Remote();
    email = _Email();
  });

  tearDown(() {
    queue?.dispose();
    queue = null;
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  Future<void> setLocale(String locale) => writer.execute(
    Sql.named(
      'INSERT INTO public.notification_preference (account_id, locale) '
      'VALUES (@a, @l) '
      'ON CONFLICT (account_id) DO UPDATE SET locale = EXCLUDED.locale',
    ),
    parameters: {'a': _forwarder, 'l': locale},
  );

  Future<void> revokeAccess() async {
    await writer.execute(
      Sql.named(
        'DELETE FROM public.beacon_forward_edge WHERE recipient_id = @r',
      ),
      parameters: {'r': _forwarder},
    );
    await writer.execute(
      Sql.named('DELETE FROM public.beacon_participant WHERE user_id = @r'),
      parameters: {'r': _forwarder},
    );
    expect(await _canRead(writer), isFalse, reason: 'access really revoked');
  }

  Future<void> retitle(String title) => writer.execute(
    Sql.named('UPDATE public.beacon SET title = @t WHERE id = @i'),
    parameters: {'t': title, 'i': _request},
  );

  AttentionChannelDecision decision({
    String storedTitle = _staleTitle,
    bool done = false,
  }) {
    final content = ForwardHelpedContent(
      beaconTitle: storedTitle,
      helperId: 'Ufhgatehelp1',
      path: const [
        HelpPathNode.named(userId: 'Ufhgatepath01', displayName: 'Anna'),
        HelpPathNode.named(userId: 'Ufhgatehelp1', displayName: 'Vera'),
      ],
      done: done,
    );
    return AttentionChannelDecision(
      receiptId: 'Rfhgate00001',
      recipientId: _forwarder,
      kind: NotificationKind.commitmentEvent,
      priority: NotificationPriority.normal,
      title: 'Your forward helped',
      body: 'A helper offered help and was accepted.',
      actionUrl: '/#/beacon/view/$_request',
      dedupKey: 'forward_helped:$_request:$_forwarder',
      actorUserId: '',
      reason: 'pathForwarder',
      presentationKey: 'forward_helped',
      presentationPayload: content.toPayload(),
      beaconId: _request,
      forwardHelped: content,
    );
  }

  Future<List<FcmNotificationEntity>> deliver(
    AttentionChannelDecision job,
  ) async {
    final logger = Logger('ForwardHelpedGate');
    queue = FcmBatchQueue(remote, logger);
    final service = BeaconNotificationService(
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
    await service.handOffChannels([job]);
    final deadline = DateTime.timestamp().add(const Duration(seconds: 3));
    while (remote.sent.isEmpty && DateTime.timestamp().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return remote.sent;
  }

  group('a forwarder who cannot read the Request gets a generic push', () {
    test('English: generic title and a body naming the path only', () async {
      await revokeAccess();
      final sent = await deliver(decision());
      expect(sent, hasLength(1));
      expect(sent.single.title, 'Your forward helped');
      expect(sent.single.body, 'Anna → Vera offered help');
    });

    test('Russian: the same push in Russian', () async {
      await setLocale('ru');
      await revokeAccess();
      final sent = await deliver(decision());
      expect(sent, hasLength(1));
      expect(sent.single.title, 'Ваша пересылка помогла');
      expect(sent.single.body, isNotEmpty);
      expect(sent.single.body, endsWith('предложил(а) помощь'));
      for (final text in [sent.single.title, sent.single.body]) {
        expect(text, isNot(contains(_staleTitle)));
        expect(text, isNot(contains(_liveTitle)));
      }
    });

    test('neither the stored nor the live Request title is revealed', () async {
      await revokeAccess();
      final sent = await deliver(decision());
      expect(sent, hasLength(1));
      for (final text in [sent.single.title, sent.single.body]) {
        expect(text, isNotEmpty);
        expect(text, isNot(contains(_staleTitle)));
        expect(text, isNot(contains(_liveTitle)));
      }
    });

    test('a completed Request names the helper but no title', () async {
      await revokeAccess();
      final sent = await deliver(decision(done: true));
      expect(sent, hasLength(1));
      expect(sent.single.body, "Completed with Vera's help");
      for (final text in [sent.single.title, sent.single.body]) {
        expect(text, isNot(contains(_liveTitle)));
        expect(text, isNot(contains(_staleTitle)));
      }
    });
  });

  group('a forwarder who can read the Request gets the live title', () {
    test(
      'an empty stored title still gives a titled push with a body',
      () async {
        expect(await _canRead(writer), isTrue);
        final sent = await deliver(decision(storedTitle: ''));
        expect(sent, hasLength(1));
        expect(sent.single.title, _liveTitle);
        expect(
          sent.single.body,
          'Anna → Vera offered help with «$_liveTitle»',
        );
      },
    );

    test(
      'a Request renamed after the event shows only the new title',
      () async {
        await retitle('Fix the barn');
        final sent = await deliver(decision(storedTitle: _staleTitle));
        expect(sent, hasLength(1));
        expect(sent.single.title, 'Fix the barn');
        expect(sent.single.body, contains('«Fix the barn»'));
        for (final text in [sent.single.title, sent.single.body]) {
          expect(text, isNot(contains(_staleTitle)));
          expect(text, isNot(contains(_liveTitle)));
        }
      },
    );

    test('a completed Request is announced under its live title', () async {
      final sent = await deliver(decision(done: true));
      expect(sent, hasLength(1));
      expect(sent.single.title, _liveTitle);
      expect(sent.single.body, "«$_liveTitle» was completed with Vera's help");
    });

    test('Russian: titled push with the Russian sentence', () async {
      await setLocale('ru');
      final sent = await deliver(decision());
      expect(sent, hasLength(1));
      expect(sent.single.title, _liveTitle);
      expect(
        sent.single.body,
        'Anna → Vera предложил(а) помощь с «$_liveTitle»',
      );
    });
  });

  group('the immediate email handed off follows the same gate', () {
    test(
      'an unreadable recipient gets no Request title in the email',
      () async {
        await revokeAccess();
        await deliver(decision());
        expect(email.calls, hasLength(1));
        final call = email.calls.single;
        expect(call.title, 'Your forward helped');
        expect(call.body, isNotEmpty);
        for (final text in [call.title, call.body]) {
          expect(text, isNot(contains(_staleTitle)));
          expect(text, isNot(contains(_liveTitle)));
        }
      },
    );

    test(
      'a readable recipient gets the live title, not the stale one',
      () async {
        await deliver(decision());
        expect(email.calls, hasLength(1));
        final call = email.calls.single;
        expect('${call.title} ${call.body}', contains(_liveTitle));
        expect(call.title, isNot(contains(_staleTitle)));
        expect(call.body, isNot(contains(_staleTitle)));
        expect(call.body, isNotEmpty);
      },
    );
  });
}

Future<bool> _canRead(Connection writer) async {
  final rows = await writer.execute(
    Sql.named('SELECT public.beacon_can_read_content(@b, @u)'),
    parameters: {'b': _request, 'u': _forwarder},
  );
  return rows.single[0]! as bool;
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
  for (final (id, name) in [(_author, 'Owner'), (_forwarder, 'Boris')]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$name', 'key-$id')
''');
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at, end_at,
   is_discoverable)
VALUES ('$_request', '$_author', '$_liveTitle', '', 0, 0, now(),
  now() + interval '3 days', false)
''');
  await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pfhgate00001', '$_request', '$_forwarder', 0, 0, 3)
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

typedef _EmailCall = ({String title, String body});

final class _Email extends Fake implements EmailNotificationPort {
  final calls = <_EmailCall>[];

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
    NotificationCopy? copy,
  }) async {
    calls.add((title: title, body: body));
    return false;
  }
}
