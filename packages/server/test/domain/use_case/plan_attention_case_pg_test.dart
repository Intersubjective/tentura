@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/plan/plan.dart';
import 'package:tentura_server/consts/beacon_plan_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/plan_cases.dart';

const _author = 'Uplanatt_au1';
const _helper = 'Uplanatt_hl1';
const _member = 'Uplanatt_mb1';

const _request = 'Bplanatt_rq1';
const _copy = 'Bplanatt_cp1';

const _a = 'PS0000000000aa';
const _b = 'PS0000000000ab';

/// Plan presentation keys that must never reach For You (owner rule D12).
const _forYouForbidden = {
  'plan_step_due',
  'plan_step_turn',
  'plan_change_pending',
  'plan_step_reminder',
  'plan_step_overdue',
};

typedef _Row = ({
  String account,
  String type,
  String? step,
  String? settlement,
});

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PLAN_ATTENTION_CASE_TEST_DB',
    defaultNamePrefix: 'tentura_test_plan_attention_case',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late PlanCases cases;
  late AttentionRepository query;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    cases = PlanCases(database, target.databaseEnv);
    query = AttentionRepository(database);
  });

  setUp(() => _resetFixture(writer));

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  Future<List<_Row>> receipts({bool liveOnly = false}) async {
    final rows = await writer.execute('''
SELECT outbox.account_id, occ.event_type, outbox.coordination_item_id,
       outbox.settlement_kind::text
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = '$_request'
  AND occ.event_type LIKE 'plan%'
  ${liveOnly ? 'AND outbox.settlement_kind IS NULL' : ''}
ORDER BY outbox.created_at, outbox.id
''');
    return [
      for (final r in rows)
        (
          account: r[0]! as String,
          type: r[1]! as String,
          step: r[2] as String?,
          settlement: r[3] as String?,
        ),
    ];
  }

  Future<List<_Row>> obligations() async => [
    for (final r in await receipts(liveOnly: true))
      if (r.type == 'planStepDue' ||
          r.type == 'planStepTurn' ||
          r.type == 'planChangePending')
        r,
  ];

  Future<void> save(List<PlanStepSnapshot> steps, {int base = 0}) =>
      cases.plan.save(
        actorId: _author,
        beaconId: _request,
        baseSeq: base,
        stepsJson: PlanSnapshot(steps).encode(),
      );

  final now = DateTime.timestamp();
  PlanStepSnapshot step(
    String id, {
    String? who,
    Duration? start,
  }) => PlanStepSnapshot(
    id: id,
    title: 'Step $id',
    assigneeId: who,
    startAt: start == null ? null : now.add(start),
  );

  test('a step whose start has come is its assignee obligation', () async {
    await save([
      step(_a, who: _helper, start: const Duration(minutes: -1)),
      step(_b, who: _member),
    ]);
    final live = await obligations();
    expect(
      live.map((r) => (r.account, r.type, r.step)),
      unorderedEquals([
        (_helper, 'planStepDue', _a),
        (_helper, 'planChangePending', null),
        (_member, 'planChangePending', null),
      ]),
    );
    // The second step waits for the first one to be ticked.
    expect(live.where((r) => r.account == _member && r.step == _b), isEmpty);
  });

  test('ticking resolves the step obligation and hands the turn on', () async {
    await save([
      step(_a, who: _helper, start: const Duration(minutes: -1)),
      step(_b, who: _member),
    ]);
    await cases.plan.setDone(actorId: _helper, stepId: _a, done: true);

    final all = await receipts();
    expect(
      all.singleWhere((r) => r.type == 'planStepDue').settlement,
      'resolved',
    );
    final live = await obligations();
    expect(
      live
          .where((r) => r.type != 'planChangePending')
          .map(
            (r) => (r.account, r.type, r.step),
          ),
      [(_member, 'planStepTurn', _b)],
    );
    // The tick is ambient news for the others, never for the one who ticked.
    final done = all.where((r) => r.type == 'planStepDone');
    expect(done.map((r) => r.account), unorderedEquals([_author, _member]));

    // Unticking takes the turn back: the member's turn is superseded and
    // the helper owes the step again.
    await cases.plan.setDone(actorId: _helper, stepId: _a, done: false);
    final again = await obligations();
    expect(
      again
          .where((r) => r.type != 'planChangePending')
          .map(
            (r) => (r.account, r.type, r.step),
          ),
      [(_helper, 'planStepDue', _a)],
    );
  });

  test('ack resolves the pending change; a new edit renews it', () async {
    await save([step(_a, who: _helper)]);
    await cases.plan.ack(actorId: _helper, beaconId: _request, uptoSeq: 1);
    final pending = (await receipts()).where(
      (r) => r.type == 'planChangePending',
    );
    expect(pending.single.settlement, 'resolved');

    await save([
      step(_a, who: _helper, start: const Duration(hours: 2)),
    ], base: 1);
    final live = (await obligations()).where(
      (r) => r.type == 'planChangePending',
    );
    expect(live.single.account, _helper);
  });

  test('a revision tells the room ambiently, not the editor', () async {
    await save([step(_a, who: _helper)]);
    final edited = (await receipts()).where((r) => r.type == 'planEdited');
    // The helper got a pending change instead; the author edited.
    expect(edited.map((r) => r.account), [_member]);
  });

  test('cant make tells the author', () async {
    await save([step(_a, who: _helper, start: const Duration(minutes: -1))]);
    await cases.plan.cantMake(
      actorId: _helper,
      stepId: _a,
      option: PlanCantMakeOption.reschedule,
      baseSeq: 1,
      newStartAt: now.add(const Duration(hours: 1)),
    );
    final all = await receipts();
    expect(
      all.where((r) => r.type == 'planCantMake').map((r) => r.account),
      [_author],
    );
    // The step moved into the future: the due obligation is superseded.
    expect(
      all.singleWhere((r) => r.type == 'planStepDue').settlement,
      'superseded',
    );
  });

  test('closing the Request supersedes every plan obligation', () async {
    await save([
      step(_a, who: _helper, start: const Duration(minutes: -1)),
      step(_b, who: _member),
    ]);
    expect(await obligations(), isNotEmpty);
    await writer.execute(
      "UPDATE public.beacon SET status = 6 WHERE id = '$_request'",
    );
    await cases.attention.onRequestStatusChanged(
      beaconId: _request,
      actorId: _author,
    );
    expect(await obligations(), isEmpty);

    // Reopen brings the owed ones back.
    await writer.execute(
      "UPDATE public.beacon SET status = 0 WHERE id = '$_request'",
    );
    await cases.transactional.runAction<void>(
      actorUserId: _author,
      action: (_) => cases.attention.onRequestStatusChanged(
        beaconId: _request,
        actorId: _author,
      ),
    );
    expect(
      (await obligations()).map((r) => (r.account, r.type)),
      contains((_helper, 'planStepDue')),
    );
  });

  test('For You never shows plan obligations', () async {
    await save([
      step(_a, who: _helper, start: const Duration(minutes: -1)),
      step(_b, who: _member),
    ]);
    await cases.plan.setDone(actorId: _helper, stepId: _a, done: true);
    expect(
      (await obligations()).map((r) => r.account).toSet(),
      containsAll([_helper, _member]),
    );

    for (final user in [_helper, _member]) {
      final forYou = await query.attentionFeed(
        accountId: user,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      final keys = [
        for (final item in forYou.page.items) ...[
          item.presentationKey,
          for (final child in item.eventsPreview) child.presentationKey,
        ],
      ];
      expect(keys.where(_forYouForbidden.contains), isEmpty, reason: user);

      // They are on the obligation surface instead.
      final myWork = await query.attentionFeed(
        accountId: user,
        view: AttentionFeedView.needsYou,
        surface: AttentionSurface.myWork,
      );
      expect(
        myWork.page.items.map((i) => i.presentationKey),
        anyElement(isIn(_forYouForbidden)),
        reason: user,
      );
    }

    // The helper's only receipts are plan obligations: no For You dot.
    final helperSummary = await query.surfaceSummary(accountId: _helper);
    expect(helperSummary.forYouDot, isFalse);
    expect(helperSummary.forYouSweepEligible, isFalse);
  });

  test('a fork copy starts without assignees and says so on publish', () async {
    await save([
      step(_a, who: _helper, start: const Duration(minutes: -1)),
      step(_b, who: _member),
    ]);
    await cases.transactional.runAction<void>(
      actorUserId: _author,
      action: (_) => cases.plan.copyPlan(
        actorId: _author,
        sourceBeaconId: _request,
        targetBeaconId: _copy,
        stepTimes: {
          _a: (startAt: now.add(const Duration(days: 1)), endAt: null),
        },
      ),
    );
    await writer.execute(
      'UPDATE public.beacon SET status = 0, published_at = now() '
      "WHERE id = '$_copy'",
    );
    await cases.transactional.runAction<void>(
      actorUserId: _author,
      action: (transaction) => cases.plan.onPublished(
        transaction: transaction,
        beaconId: _copy,
        actorId: _author,
      ),
    );

    final steps = await writer.execute('''
SELECT target_person_id, start_at IS NOT NULL
FROM public.coordination_item
WHERE beacon_id = '$_copy' AND kind = 6
ORDER BY ordering, created_seq, id
''');
    expect(steps.map((r) => r.toList()), [
      [null, true],
      [null, false],
    ]);
    final line = await writer.execute('''
SELECT semantic_marker FROM public.beacon_room_message
WHERE beacon_id = '$_copy'
''');
    expect(line.map((r) => r[0]), [BeaconRoomSemanticMarker.planCopied]);
    final copyObligations = await writer.execute('''
SELECT count(*) FROM public.notification_outbox
WHERE beacon_id = '$_copy' AND requires_action AND settlement_kind IS NULL
''');
    expect(copyObligations.single[0], 0);
  });
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_plan_sweep_mark,
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_plan_member,
  public.beacon_plan_revision,
  public.beacon_plan,
  public.coordination_item,
  public.beacon_activity_event,
  public.beacon_room_message,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_author, _helper, _member];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('planatt', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now()),
       ('$_copy', '$_author', 'Copy', '', 3, NULL)
''');
  var n = 0;
  for (final user in [_helper, _member]) {
    await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pplanatt${(n++).toString().padLeft(4, '0')}', '$_request', '$user', 0, 0, 3)
''');
  }
}
