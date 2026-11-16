@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_user_block_repository.dart';

const _author = 'Unfpdisp00001';
const _member = 'Unfpdisp00002';
const _outsider = 'Unfpdisp00003';
const _member2 = 'Unfpdisp00004';
const _request = 'Bnfpdisp00001';

/// Notices produced by the real intent builders on a real database: the
/// stored receipt (`notification_outbox.presentation_payload`) and what the
/// attention reads serve both carry the facts the notice needs.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_NOTIFICATION_FACT_PAYLOAD_DISPATCH_TEST_DB',
    defaultNamePrefix: 'tentura_test_notification_fact_dispatch',
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
  late AttentionRepository feed;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    feed = AttentionRepository(database);
    attention = TransactionalAttentionCase(
      MutatingUnitOfWork(database),
      AttentionDispatchRepository(database, Logger('NotificationFactDispatch')),
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

  setUp(() => _resetFixture(writer));

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  Future<void> record(AttentionDispatchIntent intent) => attention.runAction(
    actorUserId: intent.actorUserId,
    action: (transaction) => transaction.record(intent),
  );

  /// Payload of [account]'s receipt for [eventType]: as stored, and as served
  /// by the feed and the Request history (every copy found).
  Future<({Map<String, Object?> stored, List<Map<String, Object?>> served})>
  readback(String account, String eventType) async {
    final rows = await writer.execute(
      Sql.named(
        'SELECT presentation_payload::text FROM public.notification_outbox '
        "WHERE account_id = @a AND presentation_payload->>'eventType' = @e",
      ),
      parameters: {'a': account, 'e': eventType},
    );
    expect(rows, hasLength(1), reason: 'one stored $eventType receipt');
    final stored =
        jsonDecode(rows.single[0]! as String) as Map<String, Object?>;

    final receipts = <AttentionReceipt>[];
    for (final surface in AttentionSurface.values) {
      final page = await feed.attentionFeed(
        accountId: account,
        view: AttentionFeedView.all,
        surface: surface,
      );
      for (final item in page.page.items) {
        receipts.addAll([item, ...item.eventsPreview]);
      }
    }
    receipts.addAll(
      (await feed.attentionRequestHistory(
        accountId: account,
        beaconId: _request,
      )).items,
    );
    final served = <Map<String, Object?>>[
      for (final r in receipts)
        if (r.presentationPayload['eventType'] == eventType)
          jsonDecode(
                QueryAttention.mapReceiptForTesting(
                      r,
                    )['presentationPayloadJson']!
                    as String,
              )
              as Map<String, Object?>,
    ];
    expect(served, isNotEmpty, reason: '$eventType is readable in the feed');
    return (stored: stored, served: served);
  }

  void expectFact(
    ({Map<String, Object?> stored, List<Map<String, Object?>> served}) r,
    String key,
    Object? expected,
  ) {
    expect(r.stored[key], expected, reason: 'stored $key');
    for (final payload in r.served) {
      expect(payload[key], expected, reason: 'served $key');
    }
  }

  group('deadline notices', () {
    test('a changed deadline reaches the committed participant with the new '
        'deadline', () async {
      await record(
        await intents.deadlineChanged(
          beaconId: _request,
          actorUserId: _author,
          participantUserIds: {_member},
          oldEndAt: DateTime.utc(2026, 11, 20),
          newEndAt: DateTime.utc(2026, 11, 21, 15),
          sourceEventKey: 'deadline:$_request:1',
        ),
      );

      expectFact(
        await readback(_member, 'deadlineChanged'),
        'newEndAt',
        '2026-11-21T15:00:00.000Z',
      );
    });

    test('a removed deadline carries no new deadline', () async {
      await record(
        await intents.deadlineChanged(
          beaconId: _request,
          actorUserId: _author,
          participantUserIds: {_member},
          oldEndAt: DateTime.utc(2026, 11, 20),
          newEndAt: null,
          sourceEventKey: 'deadline:$_request:2',
        ),
      );

      final r = await readback(_member, 'deadlineChanged');
      expect(r.stored['newEndAt'], isNull);
      expect(r.stored['eventType'], 'deadlineChanged');
      for (final payload in r.served) {
        expect(payload['newEndAt'], isNull);
      }
    });

    test('a deadline reminder carries the deadline', () async {
      await record(
        await intents.deadlineReminder(
          beaconId: _request,
          participantUserIds: {_member},
          deadline: DateTime.utc(2026, 11, 17, 9),
          sourceEventKey: 'deadline_reminder:$_request',
        ),
      );

      expectFact(
        await readback(_member, 'deadlineReminder'),
        'newEndAt',
        '2026-11-17T09:00:00.000Z',
      );
    });
  });

  group('request status notice', () {
    test('a cancelled Request tells members what status it had before', () async {
      await record(
        await intents.requestStatusChanged(
          beaconId: _request,
          fromStatus: BeaconStatus.open.name,
          toStatus: BeaconStatus.cancelled.name,
          sourceEventKey: 'status:$_request:1',
          actorUserId: _author,
        ),
      );

      for (final recipient in [_member, _member2]) {
        final r = await readback(recipient, 'requestStatusChanged');
        expectFact(r, 'toStatus', 'cancelled');
        expectFact(r, 'fromStatus', 'open');
      }
    });
  });

  group('room message excerpt', () {
    Future<({Map<String, Object?> stored, List<Map<String, Object?>> served})>
    post(String recipient, {bool questions = false}) async {
      await record(
        await intents.roomMessagePosted(
          beaconId: _request,
          messageId: 'Rnfpdisp0001',
          actorUserId: _author,
          recipientUserIds: {recipient},
          excerpt: 'See you at 6',
          sourceEventKey: 'room:Rnfpdisp0001:$recipient',
          questionsScope: questions,
        ),
      );
      return readback(recipient, 'roomMessagePosted');
    }

    test('a member who can read the Request gets the General message words',
        () async {
      expectFact(await post(_member), 'excerpt', 'See you at 6');
    });

    test('a recipient who cannot read the Request gets no words', () async {
      await record(
        await intents.roomMessagePosted(
          beaconId: _request,
          messageId: 'Rnfpdisp0002',
          actorUserId: _author,
          recipientUserIds: {_outsider},
          excerpt: 'See you at 6',
          sourceEventKey: 'room:Rnfpdisp0002:$_outsider',
        ),
      );
      // Not readable, so the feed shows it to nobody: check what is stored,
      // and that the words are absent but the field is present.
      final rows = await writer.execute(
        Sql.named(
          'SELECT presentation_payload::text FROM public.notification_outbox '
          "WHERE account_id = @a AND presentation_payload->>'eventType' = "
          "'roomMessagePosted'",
        ),
        parameters: {'a': _outsider},
      );
      expect(rows, hasLength(1));
      final stored =
          jsonDecode(rows.single[0]! as String) as Map<String, Object?>;
      expect(stored['excerpt'], '');
      expect(jsonEncode(stored), isNot(contains('See you at 6')));
    });

    test('a Questions message gets no words for anyone', () async {
      expectFact(await post(_member, questions: true), 'excerpt', '');
    });
  });

  group('help offer notice', () {
    Future<({Map<String, Object?> stored, List<Map<String, Object?>> served})>
    offer({required bool backup}) async {
      await record(
        await intents.helpOfferSubmitted(
          beaconId: _request,
          helpOffererId: _member,
          authorId: _author,
          sourceEventKey: 'offer:$_request:$_member',
          isBackupOffer: backup,
        ),
      );
      return readback(_author, 'helpOfferSubmitted');
    }

    test('a backup offer reaches the author flagged as a backup', () async {
      expectFact(await offer(backup: true), 'isBackupOffer', true);
    });

    test('a regular offer is not flagged as a backup', () async {
      final r = await offer(backup: false);
      expect(r.stored['isBackupOffer'], anyOf(isNull, isFalse));
    });
  });

  group('plan step notices', () {
    for (final (eventType, minutes) in [
      (AttentionEventType.planStepReminder, 15),
      (AttentionEventType.planStepLate, 45),
    ]) {
      test('${eventType.name} carries its offset in minutes', () async {
        await record(
          await intents.planEvent(
            eventType: eventType,
            beaconId: _request,
            beaconTitle: 'Fix the roof',
            actorUserId: null,
            recipients: {_member: AttentionRecipientReason.planStepAssignee},
            sourceEventKey: 'plan:${eventType.name}:S1',
            stepId: 'S1',
            stepTitle: 'Bring ladder',
            relativeMinutes: minutes,
          ),
        );

        expectFact(
          await readback(_member, eventType.name),
          'relativeMinutes',
          minutes,
        );
      });
    }
  });
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_author, _member, _member2, _outsider]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'key-$id')
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
VALUES ('Pnfpdisp0001', '$_request', '$_member', 0, 0, 3),
       ('Pnfpdisp0002', '$_request', '$_member2', 0, 0, 3)
''');
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
