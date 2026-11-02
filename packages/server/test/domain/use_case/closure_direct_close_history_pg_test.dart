@Tags(['pg'])
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/plan/plan.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_participant_status_bits.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/closure_receipts_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_case.dart';
import 'package:tentura_server/domain/use_case/trust_publisher_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/plan_cases.dart';

const _author = 'Uclhistaut01';
const _beacon = 'Bclhistreq01';
const _helpers = ['Uclhisthlp01', 'Uclhisthlp02', 'Uclhisthlp03'];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CLOSURE_HISTORY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_closure_history',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';
  late DisposablePgWriterSession session;
  late TenturaDb db;
  late BeaconRepository beacons;
  late ClosureRepository closures;
  late ClosureCase close;
  late PlanCases plans;

  Future<List<List<Object?>>> rows(String sql) async =>
      (await session.writer.execute(sql)).map((r) => r.toList()).toList();

  Future<void> admitHelpers(int count) async {
    final commitments = CommitmentRepository(db);
    final offers = HelpOfferRepository(db);
    final room = BeaconRoomRepository(db);
    for (final helper in _helpers.take(count)) {
      await offers.upsert(beaconId: _beacon, userId: helper);
      await room.inviteOfferUserToBeaconRoom(
        beaconId: _beacon,
        offerUserId: helper,
        authorUserId: _author,
        participantStatus: BeaconParticipantStatusBits.admitted,
      );
      for (final kind in [
        CommitmentEventKind.offered,
        CommitmentEventKind.acknowledged,
      ]) {
        await commitments.record(
          beaconId: _beacon,
          userId: helper,
          actorUserId: helper,
          kind: kind,
        );
      }
    }
    await beacons.recordBeaconStatusTransition(
      beaconId: _beacon,
      fromStatus: BeaconStatus.open,
      toStatus: BeaconStatus.enoughHelp,
      reason: BeaconLifecycleChangeReason.enoughHelp,
      actorId: _author,
    );
    expect(
      (await beacons.getBeaconById(beaconId: _beacon)).status,
      BeaconStatus.enoughHelp,
    );
    await plans.plan.save(
      actorId: _author,
      beaconId: _beacon,
      baseSeq: 0,
      stepsJson: PlanSnapshot([
        PlanStepSnapshot(
          id: 'PS0000000000aa',
          title: 'Prepare',
          assigneeId: _helpers[0],
          startAt: DateTime.timestamp().subtract(const Duration(minutes: 1)),
        ),
      ]).encode(),
    );
    expect(
      await rows('''
SELECT occ.event_type FROM public.notification_outbox o
JOIN public.attention_occurrence occ ON occ.id = o.occurrence_id
WHERE o.beacon_id = '$_beacon' AND o.settlement_kind IS NULL
  AND occ.event_type IN ('planStepDue', 'planChangePending')
'''),
      unorderedEquals([
        ['planStepDue'],
        ['planChangePending'],
      ]),
    );
    // A pending offer's author obligation also has to end on close.
    await session.writer.execute('''
INSERT INTO public.attention_occurrence
(id, source_event_key, event_type, actor_user_id, immutable_payload)
VALUES ('Oclhistoffer01', 'clhist:offer', 'helpOfferSubmitted', '${_helpers[2]}', '{}')
''');
    await session.writer.execute('''
INSERT INTO public.notification_outbox
(id, account_id, category, kind, beacon_id, title, body, action_url, priority,
 dedup_key, source_event_key, destination_kind, presentation_key, access_policy,
 requires_action, attention_thread_key, occurrence_id)
VALUES ('Nclhistoffer01', '$_author', 'beacon', 'helpOfferSubmitted', '$_beacon',
 'Offer', 'Offer', '/', 'normal', 'clhist:offer', 'clhist:offer', 'beacon',
 'help_offer_submitted', 'beacon_content', true, 'v1|clhist|offer|pending', 'Oclhistoffer01')
''');
    expect(
      await rows(
        "SELECT settlement_kind FROM public.notification_outbox WHERE id = 'Nclhistoffer01'",
      ),
      [
        [null],
      ],
    );
  }

  Future<void> expectSettledPair() async {
    expect(
      (await beacons.getBeaconById(beaconId: _beacon)).status,
      BeaconStatus.closed,
    );
    final epoch = (await closures.latestEpoch(_beacon))!;
    expect(epoch.status, ClosureEpochStatus.finalized);
    expect(epoch.finalizedAt, isNotNull);
    expect(epoch.finalizeReason, FinalizeReason.authorCloseNow.dbValue);
    expect(await closures.liveEpoch(_beacon), isNull);
    final members = await closures.members(
      beaconId: _beacon,
      epoch: epoch.epoch,
    );
    expect(members.map((m) => m.userId), unorderedEquals(_helpers.take(2)));
    expect(members.every((m) => m.activeAtOpen && m.departure == null), isTrue);
    final results = await rows('''
SELECT user_id, outcome, band, draft_flag, helped
FROM public.beacon_closure_result
WHERE beacon_id = '$_beacon' ORDER BY user_id
''');
    expect(
      results.map((r) => r.take(4).toList()),
      [
        [_helpers[0], 3, 0, 0],
        [_helpers[1], 3, 0, 0],
      ],
      reason: 'Both unjudged helpers settle as cannot judge with no peer band',
    );
    expect(results[0][4], closeTo(0.35, 1e-9));
    expect(results[1][4], results[0][4], reason: 'Default split stays equal');
    expect(await closures.split(_beacon), isEmpty);
    expect(
      await rows('''
SELECT occ.event_type, o.settlement_kind, o.settled_at IS NOT NULL
FROM public.notification_outbox o
JOIN public.attention_occurrence occ ON occ.id = o.occurrence_id
WHERE o.beacon_id = '$_beacon'
  AND occ.event_type IN ('planStepDue', 'planChangePending', 'helpOfferSubmitted')
'''),
      unorderedEquals([
        ['planStepDue', 'superseded', true],
        ['planChangePending', 'superseded', true],
        ['helpOfferSubmitted', 'superseded', true],
      ]),
      reason:
          'Closed requests owe neither plan work, change acknowledgement nor an offer answer',
    );

    final receipts = await rows('''
SELECT account_id, requires_action, cleared_at IS NULL, settlement_kind
FROM public.notification_outbox
WHERE beacon_id = '$_beacon'
  AND source_event_key LIKE 'closure_finalized:%' ORDER BY account_id
''');
    expect(
      receipts,
      unorderedEquals([
        for (final id in [_author, ..._helpers.take(2)])
          [id, false, true, null],
      ]),
    );
    expect(
      await rows('''
SELECT id FROM public.notification_outbox
WHERE beacon_id = '$_beacon' AND source_event_key LIKE 'closure_opened:%'
'''),
      isEmpty,
    );
  }

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = TenturaDb(target.databaseEnv);
      beacons = BeaconRepository(db);
      closures = ClosureRepository(db);
      final env = Env(environment: Environment.test, planEnabled: true);
      plans = PlanCases(db, env);
      final logger = Logger('ClosureDirectCloseHistoryPgTest');
      final uow = MutatingUnitOfWork(db);
      final effects = BeaconLifecycleEffectsCase(
        BeaconHierarchyOutboxRepository(db),
        env: env,
        logger: logger,
      );
      final settlement = AttentionSystemSettlementRepository(db);
      final receipts = ClosureReceiptsRepository(db);
      final finalizer = ClosureFinalizeCase.create(
        unitOfWork: uow,
        closureRepository: closures,
        beaconRepository: beacons,
        trustLedger: TrustLedgerRepository(db),
        lifecycleEffects: effects,
        attentionSystemSettlement: settlement,
        trustPublisher: TrustPublisherCase(
          TrustPublishRepository(db),
          env: env,
          logger: logger,
        ),
        receipts: receipts,
        planAttention: plans.attention,
        env: env,
        logger: logger,
      );
      close = ClosureCase(
        unitOfWork: uow,
        closureRepository: closures,
        beaconRepository: beacons,
        commitmentRepository: CommitmentRepository(db),
        helpOfferRepository: HelpOfferRepository(db),
        hierarchyRepository: FakeBeaconHierarchyRepository(),
        lifecycleEffects: effects,
        attentionSystemSettlement: settlement,
        receipts: receipts,
        finalizer: finalizer,
        planAttention: plans.attention,
        env: env,
        logger: logger,
      );
    });
    tearDownAll(() async {
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });
    setUp(() async {
      await session.writer.execute(
        'TRUNCATE public.beacon, public.attention_occurrence CASCADE',
      );
      for (final (i, user) in [_author, ..._helpers].indexed) {
        await session.writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$user', '$user', '${pgTestPublicKey('clhist', i + 1)}')
ON CONFLICT (id) DO NOTHING
''');
      }
      await session.writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_beacon', '$_author', 'Request history', '', 0, now())
''');
    });
  }

  group('Closing Enough help with two admitted helpers', () {
    test(
      'records one direct transition and preserves settled results',
      () async {
        await admitHelpers(2);
        await close.close(authorId: _author, beaconId: _beacon);
        await expectSettledPair();
        final transitions = await rows('''
SELECT (diff->>'fromStatus')::int, (diff->>'toStatus')::int, actor_id
FROM public.beacon_activity_event
WHERE beacon_id = '$_beacon'
  AND type = ${BeaconActivityEventTypeBits.beaconLifecycleChanged}
  AND (diff->>'toStatus')::int <> ${BeaconStatus.enoughHelp.smallintValue}
''');
        expect(
          transitions,
          [
            [
              BeaconStatus.enoughHelp.smallintValue,
              BeaconStatus.closed.smallintValue,
              _author,
            ],
          ],
          reason: 'Immediate close has no intermediate Final check transition',
        );
      },
      skip: skipReason,
    );

    test('emits only the final closed lifecycle event', () async {
      await admitHelpers(2);
      await close.close(authorId: _author, beaconId: _beacon);
      await expectSettledPair();
      expect(
        await rows('''
SELECT from_status, to_status, actor_user_id
FROM public.beacon_hierarchy_events WHERE source_beacon_id = '$_beacon'
ORDER BY source_sequence
'''),
        [
          [
            BeaconStatus.enoughHelp.smallintValue,
            BeaconStatus.closed.smallintValue,
            _author,
          ],
        ],
        reason: 'Source lifecycle effects must fire once for the final status',
      );
    }, skip: skipReason);

    // AC 3 n/a evidence: no client change is required for a single server row.
    // api/controllers/graphql/query/query_beacon_room.dart RoomMessageList
    // resolves through BeaconRoomCase.listMessages to listMessagesEnriched.
    // Server BeaconRoomRepository.listMessagesEnriched uses msgs.map (one
    // response row per persisted message), preserving systemMessageKind and
    // encoding systemPayload as systemPayloadJson. Client
    // features/beacon_threads/data/repository/beacon_threads_repository.dart
    // listMessages uses sorted.map(_toRoomMessageFields), preserving that JSON.
    // domain/entity/room_status_change.dart: RoomStatusChange.fromMessage reads
    // exactly one from/to pair. omitSkippedFinalCheckStatusLines returns the
    // list unchanged when no closureOpened row exists, as in a direct close.
    // features/beacon_threads/ui/widget/room_message_tile.dart renders one
    // _CenteredSystemNotice for statusChanged, using roomStatusChangedBySelf
    // or roomStatusChangedByActor and beaconStatusRowClosed (RU: Закрыт).
    // Thus a single Enough help -> Closed row cannot expand into two lines.
    // Below, exercise the actual GraphQL enrichment source for author/helper;
    // this is source-cardinality evidence, not a localized widget assertion.
    test('discussion contains one Enough help to Closed status line', () async {
      await admitHelpers(2);
      await close.close(authorId: _author, beaconId: _beacon);
      final linesByViewer = <String, List<List<Object?>>>{};
      for (final viewer in [_author, _helpers[0]]) {
        final enriched = await BeaconRoomRepository(db).listMessagesEnriched(
          beaconId: _beacon,
          viewerUserId: viewer,
        );
        final lines = enriched
            .where(
              (m) =>
                  m['systemMessageKind'] ==
                  BeaconRoomSystemMessageKind.statusChanged,
            )
            .map(
              (m) =>
                  jsonDecode(m['systemPayloadJson']! as String)
                      as Map<String, dynamic>,
            )
            .where(
              (p) => p['toStatus'] != BeaconStatus.enoughHelp.smallintValue,
            );
        linesByViewer[viewer] = lines
            .map((p) => <Object?>[p['fromStatus'], p['toStatus']])
            .toList();
      }
      expect(
        linesByViewer,
        {
          for (final viewer in [_author, _helpers[0]])
            viewer: [
              [
                BeaconStatus.enoughHelp.smallintValue,
                BeaconStatus.closed.smallintValue,
              ],
            ],
        },
        reason:
            'GraphQL room enrichment exposes one close line to author and helper',
      );
      final messages = await BeaconRoomRepository(
        db,
      ).listMessages(beaconId: _beacon);
      final statusLines = messages
          .where(
            (m) =>
                m.systemMessageKind ==
                BeaconRoomSystemMessageKind.statusChanged,
          )
          .map(
            (m) => m.systemPayload! as Map<String, dynamic>,
          )
          .where(
            (payload) =>
                payload['toStatus'] != BeaconStatus.enoughHelp.smallintValue,
          )
          .toList();
      expect(statusLines.map((p) => [p['fromStatus'], p['toStatus']]), [
        [
          BeaconStatus.enoughHelp.smallintValue,
          BeaconStatus.closed.smallintValue,
        ],
      ], reason: 'Readers see a single close line with no Final check step');
    }, skip: skipReason);
  });

  test('Three admitted helpers open Final check with one transition', () async {
    await admitHelpers(3);
    await close.close(authorId: _author, beaconId: _beacon);
    expect(
      (await beacons.getBeaconById(beaconId: _beacon)).status,
      BeaconStatus.reviewOpen,
    );
    // Include the setup's Enough help event so any extra lifecycle row,
    // including another transition back to Enough help, fails this assertion.
    expect(
      await rows('''
SELECT (diff->>'fromStatus')::int, (diff->>'toStatus')::int, actor_id,
       diff->>'reason'
FROM public.beacon_activity_event
WHERE beacon_id = '$_beacon'
  AND type = ${BeaconActivityEventTypeBits.beaconLifecycleChanged}
'''),
      unorderedEquals([
        [
          BeaconStatus.open.smallintValue,
          BeaconStatus.enoughHelp.smallintValue,
          _author,
          BeaconLifecycleChangeReason.enoughHelp,
        ],
        [
          BeaconStatus.enoughHelp.smallintValue,
          BeaconStatus.reviewOpen.smallintValue,
          _author,
          BeaconLifecycleChangeReason.closureOpened,
        ],
      ]),
      reason: 'Close records exactly one Enough help to Final check transition',
    );
    expect(
      await rows('''
SELECT account_id, requires_action, cleared_at IS NULL
FROM public.notification_outbox
WHERE beacon_id = '$_beacon' AND source_event_key LIKE 'closure_opened:%'
'''),
      unorderedEquals([
        for (final id in [_author, ..._helpers]) [id, false, true],
      ]),
      reason:
          'A genuine Final check still sends one active opened receipt per member and author',
    );
    final epoch = (await closures.liveEpoch(_beacon))!;
    expect(epoch.status, ClosureEpochStatus.evaluating);
    expect(
      (await closures.members(
        beaconId: _beacon,
        epoch: epoch.epoch,
      )).map((m) => m.userId),
      unorderedEquals(_helpers),
    );
    expect(
      await rows(
        "SELECT user_id FROM public.beacon_closure_result WHERE beacon_id = '$_beacon'",
      ),
      isEmpty,
    );
    expect(
      await rows('''
SELECT from_status, to_status FROM public.beacon_hierarchy_events
WHERE source_beacon_id = '$_beacon'
'''),
      [
        [
          BeaconStatus.enoughHelp.smallintValue,
          BeaconStatus.reviewOpen.smallintValue,
        ],
      ],
    );
    final messages = await BeaconRoomRepository(
      db,
    ).listMessages(beaconId: _beacon);
    final statuses = messages
        .where(
          (m) =>
              m.systemMessageKind == BeaconRoomSystemMessageKind.statusChanged,
        )
        .map((m) => m.systemPayload! as Map<String, dynamic>)
        .where((p) => p['toStatus'] != BeaconStatus.enoughHelp.smallintValue);
    expect(statuses.map((p) => [p['fromStatus'], p['toStatus']]), [
      [
        BeaconStatus.enoughHelp.smallintValue,
        BeaconStatus.reviewOpen.smallintValue,
      ],
    ]);
  }, skip: skipReason);
}
