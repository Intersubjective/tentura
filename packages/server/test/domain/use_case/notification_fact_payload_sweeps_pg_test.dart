@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/closure_receipts_repository.dart';
import 'package:tentura_server/data/repository/closure_reminder_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/post_expiry_warning_sweep_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/mocks/invite_seed_prompt_repository_mock.dart';

const _author = 'Unfpsweep0001';
const _other = 'Unfpsweep0002';
const _request = 'Bnfpsweep0001';
const _post = 'Bnfpsweep0002';

/// What the author reads in the attention feed after each sweep or closure
/// writer ran: the receipt's public payload must carry the facts the notice
/// needs (why a Request is stale, when a Post expires, the closure epoch and
/// result). Rows are written by the real writers and read back through
/// `attentionFeed` and the GraphQL receipt mapper.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_NOTIFICATION_FACT_PAYLOAD_SWEEPS_TEST_DB',
    defaultNamePrefix: 'tentura_test_notification_fact_sweeps',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
  });

  setUp(() => _resetFixture(writer));

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  /// The author's feed receipts with [presentationKey], as the client's
  /// GraphQL layer serves them (payload decoded from the wire JSON).
  Future<List<Map<String, Object?>>> feedPayloads(
    String presentationKey,
  ) async {
    final query = AttentionRepository(database);
    final payloads = <Map<String, Object?>>[];
    for (final surface in AttentionSurface.values) {
      final feed = await query.attentionFeed(
        accountId: _author,
        view: AttentionFeedView.all,
        surface: surface,
      );
      for (final item in feed.page.items) {
        for (final receipt in [item, ...item.eventsPreview]) {
          if (receipt.presentationKey != presentationKey) continue;
          final mapped = QueryAttention.mapReceiptForTesting(receipt);
          payloads.add(
            jsonDecode(mapped['presentationPayloadJson']! as String)
                as Map<String, Object?>,
          );
        }
      }
    }
    return payloads;
  }

  Future<Map<String, Object?>> onlyFeedPayload(String key) async {
    final payloads = await feedPayloads(key);
    expect(payloads, hasLength(1), reason: 'one $key receipt in the feed');
    return payloads.single;
  }

  group('stale Request reminder', () {
    final now = DateTime.utc(2026, 11, 16, 12);

    test('a quiet Request with no deadline says quiet and for how many whole '
        'days', () async {
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at, created_at,
   status_changed_at, end_at, is_discoverable)
VALUES ('$_request', '$_author', 'Fix the roof', '', 0, 0,
  '2026-10-27T00:00:00Z', '2026-10-27T00:00:00Z', '2026-10-27T00:00:00Z',
  NULL, false)
''');

      await ClosureReminderRepository(
        database,
      ).writeStaleRequestReminders(now: now, weekKey: '2026-W46');

      final payload = await onlyFeedPayload('request_stale');
      expect(payload['staleReason'], 'quiet');
      expect(payload['quietDays'], 20);
      expect(payload, isNot(contains('endAt')));
    });

    test('a Request whose deadline passed says deadlinePassed and when it '
        'was due', () async {
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at, created_at,
   status_changed_at, end_at, is_discoverable)
VALUES ('$_request', '$_author', 'Fix the roof', '', 0, 0,
  '2026-11-10T00:00:00Z', '2026-11-10T00:00:00Z', '2026-11-10T00:00:00Z',
  '2026-11-14T09:30:00Z', false)
''');

      await ClosureReminderRepository(
        database,
      ).writeStaleRequestReminders(now: now, weekKey: '2026-W46');

      final payload = await onlyFeedPayload('request_stale');
      expect(payload['staleReason'], 'deadlinePassed');
      expect(payload['endAt'], isA<String>());
      expect(
        DateTime.parse(payload['endAt']! as String),
        DateTime.utc(2026, 11, 14, 9, 30),
      );
      expect(payload['endAt'], endsWith('Z'), reason: 'UTC timestamp');
    });
  });

  group('closure receipts in the feed', () {
    Future<void> seedClosure() async {
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at)
VALUES ('$_request', '$_author', 'Fix the roof', '', 5, 0, now())
''');
      await writer.execute('''
INSERT INTO public.beacon_closure (beacon_id, epoch, status, opened_at, closes_at)
VALUES ('$_request', 3, 0, now() - interval '6 days',
        now() + interval '23 hours 30 minutes')
''');
      await writer.execute('''
INSERT INTO public.beacon_closure_member
  (beacon_id, epoch, user_id, departure, active_at_open)
VALUES ('$_request', 3, '$_author', NULL, true)
''');
    }

    test('a draft reminder carries the closure epoch as an integer', () async {
      await seedClosure();
      await writer.execute('''
INSERT INTO public.beacon_closure_support (beacon_id, voter_id, target_id, version)
VALUES ('$_request', '$_author', '$_other', 0)
''');

      final written = await ClosureReminderRepository(
        database,
      ).writeDraftReminders(now: DateTime.now().toUtc());
      expect(written, 1, reason: 'the draft reminder is written');

      final payload = await onlyFeedPayload('closure_draft_reminder');
      expect(payload['epoch'], 3);
    });

    test('a finalized receipt carries epoch, outcome, band and draft flag '
        'as integers', () async {
      await seedClosure();
      await writer.execute('''
INSERT INTO public.beacon_closure_result
  (beacon_id, epoch, user_id, outcome, band, draft_flag, helped)
VALUES ('$_request', 3, '$_author', 2, 1, 1, 0.5)
''');

      await ClosureReceiptsRepository(database).finalized(_request, 3);

      final payload = await onlyFeedPayload('closure_finalized');
      expect(payload['epoch'], 3);
      expect(payload['outcome'], 2);
      expect(payload['band'], 1);
      expect(payload['draftFlag'], 1);
    });
  });

  group('Post expiry warning', () {
    test('stores when the Post expires as a UTC ISO string', () async {
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at, expiry_warning_eligible)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now(),
  date_trunc('second', now()) + interval '2 hours', true)
''');
      final expiresAt =
          (await writer.execute(
                "SELECT expires_at FROM public.beacon WHERE id = '$_post'",
              )).single[0]!
              as DateTime;

      await _buildSweep(database, target.databaseEnv).runDue();

      final payload = await onlyFeedPayload('post_expiring_soon');
      expect(payload['expiresAt'], isA<String>());
      expect(DateTime.parse(payload['expiresAt']! as String), expiresAt);
      expect(payload['expiresAt'], endsWith('Z'), reason: 'UTC timestamp');
    });
  });
}

PostExpiryWarningSweepCase _buildSweep(TenturaDb db, Env env) {
  final logger = Logger('NotificationFactPayloadSweepsPgTest');
  final room = BeaconRoomRepository(db);
  final attention = TransactionalAttentionCase(
    MutatingUnitOfWork(db),
    AttentionDispatchRepository(db, logger),
  );
  final intents = AttentionIntentCase(
    BeaconRoomNotificationContextRepository(
      room,
      db,
      HelpOfferRepository(db),
      CommitmentRepository(db),
    ),
    UserRepository(
      env,
      db,
      _NoopInviteGenealogyRepository(),
      InviteSeedPromptRepositoryMock(),
    ),
    BeaconAccessRepository(db),
    FakeUserBlockRepository(),
  );
  return PostExpiryWarningSweepCase(BeaconRepository(db), intents, attention);
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_closure_result,
  public.beacon_closure_support,
  public.beacon_closure_member,
  public.beacon_closure,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$_author', '$_author', 'key-$_author'),
       ('$_other', '$_other', 'key-$_other')
''');
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
