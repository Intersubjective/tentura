@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/plan/plan.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/plan_cases.dart';

const _author = 'Uplanswp_au1';
const _helper = 'Uplanswp_hl1';

const _request = 'Bplanswp_rq1';

const _a = 'PS0000000000ba';
const _b = 'PS0000000000bb';

typedef _Row = ({String account, String type, bool channel});

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PLAN_STEP_SWEEP_CASE_TEST_DB',
    defaultNamePrefix: 'tentura_test_plan_step_sweep_case',
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

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    cases = PlanCases(database, target.databaseEnv);
  });

  setUp(() => _resetFixture(writer));

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  /// Plan receipts the sweep produced or the reconciler opened, in order.
  Future<List<_Row>> receipts({Set<String>? types, bool live = false}) async {
    final rows = await writer.execute('''
SELECT outbox.account_id, occ.event_type, rcp.channel_eligible
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
JOIN public.attention_occurrence_recipient AS rcp
  ON rcp.occurrence_id = occ.id AND rcp.account_id = outbox.account_id
WHERE outbox.beacon_id = '$_request'
  AND occ.event_type LIKE 'plan%'
  ${live ? 'AND outbox.settlement_kind IS NULL' : ''}
ORDER BY outbox.created_at, outbox.id
''');
    return [
      for (final r in rows)
        if (types == null || types.contains(r[1]))
          (
            account: r[0]! as String,
            type: r[1]! as String,
            channel: r[2]! as bool,
          ),
    ];
  }

  Future<int> changeSeq() async =>
      (await writer.execute(
            "SELECT change_seq FROM public.beacon_plan WHERE beacon_id = '$_request'",
          )).single[0]!
          as int;

  Future<int> marks() async =>
      (await writer.execute(
            'SELECT count(*) FROM public.beacon_plan_sweep_mark',
          )).single[0]!
          as int;

  // Steps start half an hour from the real clock, so a save made now is
  // well before every reminder window; the sweep runs at chosen instants.
  final start = DateTime.timestamp()
      .add(const Duration(minutes: 30))
      .copyWith(second: 0, millisecond: 0, microsecond: 0);

  Future<void> save(List<PlanStepSnapshot> steps) => cases.plan.save(
    actorId: _author,
    beaconId: _request,
    baseSeq: 0,
    stepsJson: PlanSnapshot(steps).encode(),
  );

  PlanStepSnapshot step(String id, {String? who}) => PlanStepSnapshot(
    id: id,
    title: 'Step $id',
    assigneeId: who,
    startAt: start,
  );

  test('nothing is due before the reminder window', () async {
    await save([step(_a, who: _helper)]);
    final claimed = await cases.sweep.runDue(
      now: start.subtract(const Duration(minutes: 20)),
    );
    expect(claimed, 0);
    expect(await marks(), 0);
  });

  test('a reminder goes to the assignee 15 minutes ahead, once', () async {
    await save([step(_a, who: _helper)]);
    final at = start.subtract(const Duration(minutes: 10));
    expect(await cases.sweep.runDue(now: at), 1);
    final reminders = await receipts(types: {'planStepReminder'});
    expect(reminders.map((r) => r.account), [_helper]);
    final body = await writer.execute('''
SELECT outbox.title, outbox.body FROM public.notification_outbox AS outbox
WHERE outbox.presentation_key = 'plan_step_reminder'
''');
    // Relative time only, never a clock time.
    final text = '${body.single[0]} ${body.single[1]}';
    expect(text, contains('10'));
    expect(text, isNot(matches(RegExp(r'\d{1,2}:\d{2}'))));

    // Idempotent: the same pass again claims nothing and records nothing.
    expect(await cases.sweep.runDue(now: at), 0);
    expect(
      await cases.sweep.runDue(now: at.add(const Duration(minutes: 1))),
      0,
    );
    expect(await receipts(types: {'planStepReminder'}), hasLength(1));
  });

  test('the start makes the step an obligation and bumps the head', () async {
    await save([step(_a, who: _helper)]);
    expect(await receipts(types: {'planStepDue'}), isEmpty);
    final before = await changeSeq();

    final at = start.add(const Duration(minutes: 1));
    expect(await cases.sweep.runDue(now: at), 1);
    final due = await receipts(types: {'planStepDue'}, live: true);
    expect(due.map((r) => (r.account, r.channel)), [(_helper, true)]);
    expect(await changeSeq(), greaterThan(before));

    // A second pass at the same instant, and a later one before overdue,
    // claim nothing and open no second obligation.
    expect(await cases.sweep.runDue(now: at), 0);
    expect(
      await cases.sweep.runDue(now: at.add(const Duration(minutes: 5))),
      0,
    );
    expect(await receipts(types: {'planStepDue'}), hasLength(1));
  });

  test('overdue, late and unassigned steps, each once', () async {
    await save([step(_a, who: _helper), step(_b)]);
    final at = start.add(const Duration(minutes: 50));
    // a: due, overdue, authorLate; b: unassignedDue.
    expect(await cases.sweep.runDue(now: at), 4);

    final notices = await receipts(
      types: {'planStepOverdue', 'planStepLate', 'planStepUnassigned'},
    );
    expect(
      notices.map((r) => (r.account, r.type)),
      unorderedEquals([
        (_helper, 'planStepOverdue'),
        (_author, 'planStepLate'),
        (_author, 'planStepUnassigned'),
      ]),
    );
    // Long past their boundary the overdue and unassigned notices carry no
    // push; the author's «late» is fresh (its own boundary is 5 min old).
    expect(
      {for (final r in notices) r.type: r.channel},
      {
        'planStepOverdue': false,
        'planStepLate': true,
        'planStepUnassigned': false,
      },
    );
    // The due obligation is still opened, only quietly.
    final due = await receipts(types: {'planStepDue'}, live: true);
    expect(due.map((r) => (r.account, r.channel)), [(_helper, false)]);

    // Steps whose final phase is claimed are no longer candidates.
    expect(await cases.sweep.runDue(now: at), 0);
    expect(
      await cases.sweep.runDue(now: at.add(const Duration(hours: 1))),
      0,
    );
    expect(await marks(), 4);
  });

  test('a ticked step is left alone', () async {
    await save([step(_a, who: _helper)]);
    await cases.plan.setDone(actorId: _helper, stepId: _a, done: true);
    expect(
      await cases.sweep.runDue(now: start.add(const Duration(hours: 2))),
      0,
    );
    expect(
      await receipts(
        types: {'planStepDue', 'planStepOverdue', 'planStepLate'},
      ),
      isEmpty,
    );
  });

  test('sweep notices never reach For You', () async {
    await save([step(_a, who: _helper)]);
    await cases.sweep.runDue(now: start.subtract(const Duration(minutes: 10)));
    await cases.sweep.runDue(now: start.add(const Duration(minutes: 20)));
    expect(
      (await receipts(types: {'planStepReminder', 'planStepOverdue'})).map(
        (r) => r.type,
      ),
      unorderedEquals(['planStepReminder', 'planStepOverdue']),
    );
    final forYou = await AttentionRepository(database).attentionFeed(
      accountId: _helper,
      view: AttentionFeedView.all,
      surface: AttentionSurface.activity,
    );
    final keys = [
      for (final item in forYou.page.items) ...[
        item.presentationKey,
        for (final child in item.eventsPreview) child.presentationKey,
      ],
    ];
    expect(keys.where((k) => k?.startsWith('plan_step') ?? false), isEmpty);
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
  final users = [_author, _helper];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('planswp', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pplanswp0000', '$_request', '$_helper', 0, 0, 3)
''');
}
