@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/coordination_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

// #601: a helper who opened a Request by link (never forwarded to them) had
// no `inbox_item`, and Activity builds a Request's row from `inbox_item`
// only, so their offer left no row there.
// #700: offer receipts carry the actor's display name in the presentation
// payload, so the client need not parse the English title.

const _beaconId = 'Bhoactrow01';
const _authorId = 'Uhoactauth1';
const _helperId = 'Uhoacthelp1';
const _authorName = 'Ada Author';
const _helperName = 'Hal Helper';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HELP_OFFER_ACTIVITY_ROW_TEST_DB',
    defaultNamePrefix: 'tentura_test_help_actrow',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('help offer: Activity row and actor name', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository attentionQuery;
    late _Harness harness;

    setUpAll(() async {
      if (skipReason != false) return;
      // The activity stream's provenance ranks with pgmer2's
      // `mr_mutual_scores` (see attention_activity_stream_pg_test).
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      attentionQuery = AttentionRepository(database);
      harness = _Harness.build(database, target.databaseEnv);
    });

    setUp(() async {
      if (skipReason != false) return;
      await _resetFixture(writer);
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<List<AttentionReceipt>> activityForwardRows(String accountId) async {
      final feed = await attentionQuery.attentionFeed(
        accountId: accountId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      return feed.page.items
          .where((item) => item.itemKind == AttentionItemKind.forward)
          .toList();
    }

    Future<void> insertForwardedRow() => writer.execute(
      Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@u, @b, 0, 2, '2026-08-04T09:00:00Z'::timestamptz, 'note', '')
'''),
      parameters: {'u': _helperId, 'b': _beaconId},
    );

    // The inbox row checks need no MeritRank, so the pg shard (which runs
    // with `--exclude-tags mr`) covers #601 in CI.
    test(
      'an offer on a Request opened by link gets an inbox row (#601)',
      () async {
        expect(await _inboxRow(writer, _helperId), isNull);

        await harness.helpOfferCase.offerHelp(
          beaconId: _beaconId,
          userId: _helperId,
        );

        // Not a new item in the Inbox: not an unanswered «Для вас» forward
        // (status 0), and no forward time that would sort it as fresh.
        final row = await _inboxRow(writer, _helperId);
        expect(row, isNotNull);
        expect(row!.status, 1);
        expect(row.forwardCount, 0);
        expect(row.latestForwardAt.isBefore(DateTime.utc(2000)), isTrue);
      },
      skip: skipReason,
    );

    test(
      'editing an offer made before #601 shipped gives it the inbox row',
      () async {
        await harness.helpOfferCase.offerHelp(
          beaconId: _beaconId,
          userId: _helperId,
        );
        // As if the offer predated the deploy: no inbox row.
        await writer.execute(
          Sql.named(
            'DELETE FROM public.inbox_item WHERE user_id = @u AND beacon_id = @b',
          ),
          parameters: {'u': _helperId, 'b': _beaconId},
        );
        expect(await _inboxRow(writer, _helperId), isNull);

        await harness.helpOfferCase.offerHelp(
          beaconId: _beaconId,
          userId: _helperId,
          message: 'edited',
        );

        final row = await _inboxRow(writer, _helperId);
        expect(row, isNotNull);
        expect(row!.status, 1);
        expect(row.forwardCount, 0);
      },
      skip: skipReason,
    );

    test(
      'a forwarded helper keeps their inbox row as it was (#601 guard)',
      () async {
        await insertForwardedRow();

        await harness.helpOfferCase.offerHelp(
          beaconId: _beaconId,
          userId: _helperId,
        );

        final row = await _inboxRow(writer, _helperId);
        expect(row!.status, 0);
        expect(row.forwardCount, 2);
        expect(row.latestForwardAt, DateTime.utc(2026, 8, 4, 9));
      },
      skip: skipReason,
    );

    // The Activity feed ranks provenance with MeritRank, hence `mr`.
    group('Activity feed', () {
      test(
        'an offer on a Request opened by link gets a helping Activity row',
        () async {
          await harness.helpOfferCase.offerHelp(
            beaconId: _beaconId,
            userId: _helperId,
          );

          final rows = await activityForwardRows(_helperId);
          expect(rows, hasLength(1));
          expect(rows.single.id, 'inbox:$_beaconId');
          expect(rows.single.forwardOutcome, 'helping');
        },
        skip: skipReason,
      );

      test('a forwarded helper still reads as helping', () async {
        await insertForwardedRow();

        await harness.helpOfferCase.offerHelp(
          beaconId: _beaconId,
          userId: _helperId,
        );

        final rows = await activityForwardRows(_helperId);
        expect(rows.single.forwardOutcome, 'helping');
      }, skip: skipReason);
    }, tags: ['mr']);

    test('offer receipts carry the actor display name (#700)', () async {
      await harness.helpOfferCase.offerHelp(
        beaconId: _beaconId,
        userId: _helperId,
      );
      final submitted = await _receiptPayload(
        writer,
        eventType: 'helpOfferSubmitted',
        accountId: _authorId,
      );
      expect(submitted['actorUserId'], _helperId);
      expect(submitted['actorName'], _helperName);

      await harness.coordinationCase.acceptHelpOffer(
        beaconId: _beaconId,
        offerUserId: _helperId,
        actorUserId: _authorId,
      );
      final accepted = await _receiptPayload(
        writer,
        eventType: 'offerAccepted',
        accountId: _helperId,
      );
      expect(accepted['actorUserId'], _authorId);
      expect(accepted['actorName'], _authorName);
    }, skip: skipReason);
  }, skip: skipReason);
}

typedef _InboxRow = ({int status, int forwardCount, DateTime latestForwardAt});

Future<_InboxRow?> _inboxRow(Connection writer, String userId) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT status, forward_count, latest_forward_at
FROM public.inbox_item
WHERE user_id = @u AND beacon_id = @b
'''),
    parameters: {'u': userId, 'b': _beaconId},
  );
  if (rows.isEmpty) return null;
  final row = rows.single;
  return (
    status: (row[0]! as num).toInt(),
    forwardCount: (row[1]! as num).toInt(),
    latestForwardAt: (row[2]! as DateTime).toUtc(),
  );
}

Future<Map<String, Object?>> _receiptPayload(
  Connection writer, {
  required String eventType,
  required String accountId,
}) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT outbox.presentation_payload::text
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE occ.event_type = @eventType
  AND outbox.beacon_id = @b
  AND outbox.account_id = @accountId
ORDER BY outbox.created_at DESC
LIMIT 1
'''),
    parameters: {
      'eventType': eventType,
      'b': _beaconId,
      'accountId': accountId,
    },
  );
  expect(rows, hasLength(1), reason: 'one $eventType receipt for $accountId');
  return (jsonDecode(rows.single[0]! as String) as Map).cast<String, Object?>();
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_help_offer,
  public.inbox_item,
  public.beacon,
  public."user"
CASCADE
''');
  for (final (id, name) in [
    (_authorId, _authorName),
    (_helperId, _helperName),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
      parameters: {'id': id, 'name': name, 'key': 'key-$id'},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (
  '$_beaconId', '$_authorId', 'Activity row beacon', 'desc',
  ${BeaconStatus.open.smallintValue}
)
''');
}

final class _Harness {
  const _Harness({
    required this.helpOfferCase,
    required this.coordinationCase,
    required this.systemSettlement,
  });

  final HelpOfferCase helpOfferCase;
  final CoordinationCase coordinationCase;
  final AttentionSystemSettlementRepository systemSettlement;

  static _Harness build(TenturaDb db, Env env) {
    final logger = Logger('HelpOfferActivityRowPgTest');
    final unitOfWork = MutatingUnitOfWork(db);
    final dispatch = AttentionDispatchRepository(db, logger);
    final attention = TransactionalAttentionCase(unitOfWork, dispatch);
    final systemSettlement = AttentionSystemSettlementRepository(db);
    final room = BeaconRoomRepository(db);
    final helpOffers = HelpOfferRepository(db);
    final commitments = CommitmentRepository(db);
    final beacons = BeaconRepository(db);
    final access = BeaconAccessRepository(db);
    final hierarchy = BeaconHierarchyRepository(db);
    final attentionIntents = AttentionIntentCase(
      BeaconRoomNotificationContextRepository(
        room,
        db,
        helpOffers,
        commitments,
      ),
      UserRepository(
        env,
        db,
        _NoopInviteGenealogyRepository(),
        InviteSeedPromptRepositoryMock(),
      ),
      access,
      FakeUserBlockRepository(),
    );
    final commitmentQuery = CommitmentQueryCase(
      commitments,
      helpOffers,
      env: env,
      logger: logger,
    );
    return _Harness(
      helpOfferCase: HelpOfferCase(
        helpOffers,
        beacons,
        commitments,
        InboxRepository(db),
        CapabilityCase(
          PersonCapabilityEventRepository(db),
          env: env,
          logger: logger,
        ),
        FakeBeaconAccessGuard(),
        roomRepository: room,
        attentionIntents: attentionIntents,
        attention: attention,
        attentionSystemSettlement: systemSettlement,
        env: env,
        logger: logger,
      ),
      coordinationCase: CoordinationCase(
        beacons,
        helpOffers,
        CoordinationRepository(
          db,
          DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
          VoteUserFriendshipLookup(db),
          room,
        ),
        room,
        FakeUserBlockRepository(),
        commitments,
        commitmentQuery,
        hierarchy,
        attentionIntents: attentionIntents,
        attention: attention,
        attentionSystemSettlement: systemSettlement,
        guard: FakeBeaconAccessGuard(),
        env: env,
        logger: logger,
      ),
      systemSettlement: systemSettlement,
    );
  }
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
