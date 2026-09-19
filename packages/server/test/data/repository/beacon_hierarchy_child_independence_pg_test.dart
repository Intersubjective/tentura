@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_hierarchy_delivery_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/fake_user_block_repository.dart';
import 'beacon_hierarchy_pg_helpers.dart';

/// U11 — a child Request is its own attention object (D16, R7, contract §8).
///
/// The topology under test is the canonical three-level chain, and three
/// levels is the point. A two-level suite passes even when propagation is
/// merely *delayed by one hop*, so every assertion here is made about **both**
/// ancestors of the Request that actually moved:
///
/// ```text
///   A  (grandparent, alice)
///   └── B  (parent, bob)
///       └── C  (child, dave)   ← the status change happens here
/// ```
///
/// What the unit promises, and what each test pins:
///
/// 1. C moving produces **one** delivery, to its **direct** parent B. A — an
///    ancestor, but not the direct parent — gets no notice, no receipt and no
///    room message. (`insertTopologyDeliveryTargets` is the live fan-out; this
///    suite calls it rather than hand-picking targets, so a future change that
///    made the fan-out recursive would fail here.)
/// 2. The receipt B does get is `placement = 'timeline_only'` — it is in B's
///    log, and it is excluded from B's dot, B's count and B's position on both
///    surfaces. The read-path assertions compare the *whole* surface before
///    and after the delivery: same summary, same feed order, same My Desk.
/// 3. The copy never names the source Request, whether or not the recipient
///    could read it. A propagated notice that leaked "Request C" into an
///    ancestor's log would publish a title the recipient may have no right to.
Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for child independence PG test';

  group('U11 — child propagation policy', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconHierarchyOutboxRepository outbox;
    late BeaconHierarchyDeliveryCase delivery;
    late AttentionRepository query;
    late FakeUserBlockRepository userBlocks;

    setUpAll(() async {
      if (skipReason != false) return;
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      // U10d's grouped rows rank forward provenance through `mr_mutual_scores`
      // (pgmer2). The hierarchy session does not create the extension, and the
      // read path is half of what this suite measures.
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      outbox = BeaconHierarchyOutboxRepository(session.db);
      query = AttentionRepository(session.db);
      userBlocks = FakeUserBlockRepository();
      final room = BeaconRoomRepository(session.db);
      final intents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(
          room,
          session.db,
          HelpOfferRepository(session.db),
          CommitmentRepository(session.db),
        ),
        UserRepository(
          Env(environment: Environment.test),
          session.db,
          _NoopTrustEvidenceRepository(),
          _NoopInviteGenealogyRepository(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(session.db),
        userBlocks,
      );
      delivery = BeaconHierarchyDeliveryCase(
        outbox,
        TransactionalAttentionCase(
          MutatingUnitOfWork(session.db),
          AttentionDispatchRepository(
            session.db,
            Logger('ChildIndependencePg'),
          ),
        ),
        intents,
        env: Env(environment: Environment.test),
        logger: Logger('ChildIndependencePg'),
      );
    });

    setUp(() async {
      if (skipReason != false) return;
      userBlocks.clear();
      await _cleanupAttentionArtifacts(writer);
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
    });

    tearDown(() async {
      if (skipReason != false) return;
      await _cleanupAttentionArtifacts(writer);
      await fixture.tearDown();
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await fixture.db.close();
      await writer.close();
      await target.drop();
    });

    /// Moves C — the deepest Request in the chain — through the live fan-out.
    Future<String> moveTheChild({
      BeaconStatus toStatus = BeaconStatus.closed,
      DateTime? occurredAt,
    }) async {
      final event = await outbox.recordEvent(
        sourceBeaconId: BeaconHierarchyTopology.beaconC,
        fromStatus: BeaconStatus.open,
        toStatus: toStatus,
        occurredAt: occurredAt ?? DateTime.utc(2026, 6),
        actorUserId: BeaconHierarchyTopology.daveId,
      );
      await outbox.insertTopologyDeliveryTargets(
        sourceBeaconId: BeaconHierarchyTopology.beaconC,
        eventId: event.eventId,
      );
      await delivery.runDue(workerId: 'u11-worker', now: DateTime.timestamp());
      return event.eventId;
    }

    // --------------------------------------------- one hop, and only one hop

    test(
      'a grandchild moving reaches its direct parent only — never the grandparent',
      () async {
        final eventId = await moveTheChild();

        final targets = await writer.execute(
          Sql.named('''
SELECT target_beacon_id, state
FROM public.beacon_hierarchy_deliveries
WHERE event_id = @e
ORDER BY target_beacon_id
'''),
          parameters: {'e': eventId},
        );
        expect(
          targets.map((row) => row[0]).toList(),
          [BeaconHierarchyTopology.beaconB],
          reason: 'the fan-out is one hop: the direct parent, nobody else',
        );

        // The grandparent is an ancestor too. It gets nothing at all — not a
        // quieter notice, not a timeline row: nothing.
        expect(
          await _receiptsOn(writer, BeaconHierarchyTopology.beaconA),
          isEmpty,
          reason: 'grandparent A must have no receipt from a grandchild move',
        );
        expect(
          await _hierarchyNoticesOn(writer, BeaconHierarchyTopology.beaconA),
          isEmpty,
          reason: 'grandparent A must have no hierarchy room notice either',
        );
      },
      skip: skipReason,
    );

    test(
      'the direct parent keeps the notice in its log, classified timeline_only',
      () async {
        await moveTheChild();

        final notices = await _hierarchyNoticesOn(
          writer,
          BeaconHierarchyTopology.beaconB,
        );
        expect(
          notices,
          hasLength(1),
          reason: "the parent's log stays complete — D16 keeps the notice",
        );

        final receipts = await _receiptsOn(
          writer,
          BeaconHierarchyTopology.beaconB,
        );
        expect(receipts, isNotEmpty);
        for (final receipt in receipts) {
          expect(
            receipt['placement'],
            'timeline_only',
            reason:
                'a propagated hierarchy notice is timeline-only by producer '
                'policy, for every recipient of it',
          );
          expect(
            receipt['requires_action'],
            isFalse,
            reason: 'timeline-only is a placement, never an obligation',
          );
        }
      },
      skip: skipReason,
    );

    // ------------------------------- the ancestors' surfaces do not move

    test(
      'no dot, no count and no position change on either ancestor, both surfaces',
      () async {
        // Two viewers, deliberately, because the parent sits on a *different*
        // surface for each and the read path computes the two from different
        // SQL. Bob authors B, so B is on his My Desk. Alice was forwarded B
        // and is not responsible for it, so for her B is a grouped row on
        // For You — the `event_total` / `event_unseen_count` / `MIN(created_at)`
        // path, which is where a propagated child notice would otherwise
        // materialise a card out of nothing.
        //
        // Alice's inbox row is also what makes her a recipient of the notice
        // at all (`inboxStanceUserIds`), so her half of this test is not
        // vacuous: she really does receive the receipt whose placement is
        // under test. The `receiptsFor` assertion below pins that.
        await _inboxItem(
          writer,
          userId: BeaconHierarchyTopology.aliceId,
          beaconId: BeaconHierarchyTopology.beaconB,
          latestForwardAt: '2026-01-02T00:00:00Z',
        );
        await _optionalReceipt(
          writer,
          id: 'NOu11base01',
          accountId: BeaconHierarchyTopology.bobId,
          beaconId: BeaconHierarchyTopology.beaconB,
          createdAt: '2026-05-01T10:00:00Z',
        );
        await _optionalReceipt(
          writer,
          id: 'NOu11base02',
          accountId: BeaconHierarchyTopology.bobId,
          beaconId: BeaconHierarchyTopology.beaconA,
          createdAt: '2026-05-02T10:00:00Z',
        );
        await _optionalReceipt(
          writer,
          id: 'NOu11base03',
          accountId: BeaconHierarchyTopology.aliceId,
          beaconId: BeaconHierarchyTopology.beaconB,
          createdAt: '2026-05-03T10:00:00Z',
        );
        await _optionalReceipt(
          writer,
          id: 'NOu11base04',
          accountId: BeaconHierarchyTopology.aliceId,
          beaconId: BeaconHierarchyTopology.beaconA,
          createdAt: '2026-05-04T10:00:00Z',
        );

        final ancestors = {
          BeaconHierarchyTopology.beaconA,
          BeaconHierarchyTopology.beaconB,
        };
        for (final viewer in [
          BeaconHierarchyTopology.bobId,
          BeaconHierarchyTopology.aliceId,
        ]) {
          final before = await _surfaceState(query, viewer, ancestors);
          expect(
            [...before['myWork']! as List, ...before['feed']! as List],
            isNotEmpty,
            reason: 'viewer $viewer must have something to keep unchanged',
          );

          await moveTheChild(occurredAt: DateTime.utc(2026, 7));

          final receipts = await _receiptsOn(
            writer,
            BeaconHierarchyTopology.beaconB,
          );
          expect(
            receipts.map((row) => row['account_id']),
            contains(viewer),
            reason:
                'viewer $viewer must actually receive the propagated notice, '
                'or this assertion proves nothing about its placement',
          );

          final after = await _surfaceState(query, viewer, ancestors);
          expect(
            after,
            before,
            reason:
                'viewer $viewer: a grandchild moving must change no dot, no '
                'count and no position on A or B, on For You or My Desk',
          );

          await _cleanupAttentionArtifacts(writer, keepSeededReceipts: true);
        }
      },
      skip: skipReason,
    );

    // ------------------------------------------------- generic copy

    test(
      'the propagated copy never names the source Request',
      () async {
        await moveTheChild();

        final notices = await _hierarchyNoticesOn(
          writer,
          BeaconHierarchyTopology.beaconB,
        );
        final receipts = await _receiptsOn(
          writer,
          BeaconHierarchyTopology.beaconB,
        );
        // 'Request C' is the seeded title of the source, and dave its author.
        // Neither may appear in an ancestor's log: the recipient of the notice
        // is not necessarily allowed to read the Request that moved.
        for (final text in [
          ...notices.map((row) => row['body']! as String),
          ...receipts.map((row) => '${row['title']} ${row['body']}'),
        ]) {
          expect(text, isNot(contains('Request C')));
          expect(text, isNot(contains(BeaconHierarchyTopology.beaconC)));
          expect(text, isNot(contains(BeaconHierarchyTopology.daveId)));
          expect(
            text.trim(),
            isNotEmpty,
            reason: 'generic is not the same as empty',
          );
        }

        // And the generic form is reached the same way for a recipient who
        // *can* read the source as for one who cannot: the producer has no
        // per-recipient branch here, so there is nothing to get wrong later
        // only for the unreadable case. Dave authors C and can read it; the
        // body he would see is the body everybody sees.
        expect(
          notices.map((row) => row['body']).toSet(),
          hasLength(1),
          reason: 'one generic body, not a per-recipient one',
        );
      },
      skip: skipReason,
    );
  });
}

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

/// Everything a surface shows about [beaconIds], flattened so that a single
/// `expect(after, before)` covers dot, count and position at once.
Future<Map<String, Object?>> _surfaceState(
  AttentionRepository query,
  String viewer,
  Set<String> beaconIds,
) async {
  final summary = await query.surfaceSummary(accountId: viewer);
  final myWork = await query.myWorkAttention(
    accountId: viewer,
    beaconIds: beaconIds,
  );
  final offers = await query.activityOffers(accountId: viewer);
  final feed = await query.attentionFeed(
    accountId: viewer,
    view: AttentionFeedView.all,
    surface: AttentionSurface.activity,
  );
  final dotted = await query.unreadForBeacons(
    accountId: viewer,
    beaconIds: beaconIds,
  );
  return {
    'activityUnreadTotal': summary.activityUnreadTotal,
    'myWorkUnreadTotal': summary.myWorkUnreadTotal,
    'needsYouTotal': summary.needsYouTotal,
    // Order is part of the value: this list is the position assertion.
    'myWork': [
      for (final group in myWork)
        [
          group.beaconId,
          group.unseenCount,
          group.liveObligations.length,
          group.needsYouAt,
          group.firstEntryAt,
        ].join('|'),
    ],
    // Position, dot and count of every For You row, in list order. The
    // grouped counts belong here: `eventTotal` is what a card says out loud,
    // and a propagated child notice inflating it is exactly the R7 failure.
    'feed': [
      for (final item in feed.page.items)
        [
          item.id,
          item.isActiveAttention,
          item.createdAt,
          item.eventTotal,
          item.eventUnseenCount,
          item.eventsPreview.length,
        ].join('|'),
    ],
    'offersTotal': offers.totalCount,
    'offers': [
      for (final row in offers.items)
        [
          row.beaconId,
          row.listPositionAt,
          row.effectiveActivityAt,
          row.unseen,
          row.eventTotal,
          row.eventUnseenCount,
          row.eventsPreview.length,
        ].join('|'),
    ],
    'dotted': dotted.toList()..sort(),
  };
}

Future<List<Map<String, Object?>>> _receiptsOn(
  Connection writer,
  String beaconId,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT o.id, o.account_id, o.placement, o.requires_action, o.title, o.body
FROM public.notification_outbox o
JOIN public.attention_occurrence occ ON occ.id = o.occurrence_id
WHERE o.beacon_id = @b
  AND occ.event_type = 'beaconHierarchyStatusChanged'
ORDER BY o.account_id
'''),
    parameters: {'b': beaconId},
  );
  return [
    for (final row in rows)
      {
        'id': row[0],
        'account_id': row[1],
        'placement': row[2],
        'requires_action': row[3],
        'title': row[4],
        'body': row[5],
      },
  ];
}

Future<List<Map<String, Object?>>> _hierarchyNoticesOn(
  Connection writer,
  String beaconId,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT id, body
FROM public.beacon_room_message
WHERE beacon_id = @b AND hierarchy_notice_identity IS NOT NULL
ORDER BY id
'''),
    parameters: {'b': beaconId},
  );
  return [
    for (final row in rows) {'id': row[0], 'body': row[1]},
  ];
}

Future<void> _inboxItem(
  Connection writer, {
  required String userId,
  required String beaconId,
  required String latestForwardAt,
  int status = 0,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (
  @userId, @beaconId, @status, 1, CAST(@at AS timestamptz), '', ''
)
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = EXCLUDED.status
'''),
  parameters: {
    'userId': userId,
    'beaconId': beaconId,
    'status': status,
    'at': latestForwardAt,
  },
);

Future<void> _optionalReceipt(
  Connection writer, {
  required String id,
  required String accountId,
  required String beaconId,
  required String createdAt,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Baseline', 'Baseline body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content'
)
'''),
  parameters: {
    'id': id,
    'accountId': accountId,
    'dedupKey': 'dedup-$id',
    'createdAt': createdAt,
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
  },
);

Future<void> _cleanupAttentionArtifacts(
  Connection writer, {
  bool keepSeededReceipts = false,
}) async {
  await writer.execute(
    '''
DELETE FROM public.attention_channel_delivery
WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence WHERE source_event_key LIKE 'hierarchy:%'
)''',
  );
  await writer.execute(
    '''
DELETE FROM public.notification_outbox
WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence WHERE source_event_key LIKE 'hierarchy:%'
)''',
  );
  await writer.execute(
    '''
DELETE FROM public.attention_occurrence_recipient
WHERE occurrence_id IN (
  SELECT id FROM public.attention_occurrence WHERE source_event_key LIKE 'hierarchy:%'
)''',
  );
  await writer.execute(
    "DELETE FROM public.attention_occurrence WHERE source_event_key LIKE 'hierarchy:%'",
  );
  await writer.execute(
    "DELETE FROM public.beacon_hierarchy_deliveries WHERE event_id LIKE 'HE%'",
  );
  await writer.execute(
    "DELETE FROM public.beacon_hierarchy_events WHERE id LIKE 'HE%'",
  );
  await writer.execute(
    'DELETE FROM public.beacon_room_message '
    'WHERE hierarchy_notice_identity IS NOT NULL',
  );
  if (!keepSeededReceipts) {
    await writer.execute(
      "DELETE FROM public.notification_outbox WHERE id LIKE 'NOu11%'",
    );
    await writer.execute(
      "DELETE FROM public.inbox_item WHERE beacon_id LIKE 'Bhier%'",
    );
    await writer.execute(
      "DELETE FROM public.attention_request_state WHERE beacon_id LIKE 'Bhier%'",
    );
  }
}
