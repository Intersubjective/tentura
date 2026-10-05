@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/plan/plan.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_plan_repository.dart';
import 'package:tentura_server/domain/use_case/beacon_plan_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/plan_cases.dart';

/// `planSliceJson` (plan §4.9): the My Work / inbox plan slice is read with
/// one batched statement for every Request and shaped per viewer.
const _author = 'Uplanslice_au1';
const _helper = 'Uplanslice_hl1';
const _member = 'Uplanslice_mb1';

const _open = 'Bplanslice_op1';
const _closed = 'Bplanslice_cl1';
const _empty = 'Bplanslice_em1';

const _a = 'PS0000000000a1';
const _b = 'PS0000000000b1';
const _c = 'PS0000000000c1';
const _d = 'PS0000000000d1';

final _t0 = DateTime.utc(2030, 1, 10, 9);

PlanStepSnapshot _s(
  String id, {
  String? title,
  String? who,
  int? startMin,
  int? endMin,
}) => PlanStepSnapshot(
  id: id,
  title: title ?? 'Step $id',
  description: 'About $id',
  assigneeId: who,
  startAt: startMin == null ? null : _t0.add(Duration(minutes: startMin)),
  endAt: endMin == null ? null : _t0.add(Duration(minutes: endMin)),
);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_PLAN_SLICE_TEST_DB',
    defaultNamePrefix: 'tentura_test_beacon_plan_slice',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late BeaconPlanCase plan;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    plan = PlanCases(database, target.databaseEnv).plan;
  });

  setUp(() => _resetFixture(writer));

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  Future<void> save(
    String beaconId,
    List<PlanStepSnapshot> steps, {
    int base = 0,
    String actor = _author,
  }) => plan.save(
    actorId: actor,
    beaconId: beaconId,
    baseSeq: base,
    stepsJson: PlanSnapshot(steps).encode(),
  );

  Future<Map<String, Map<String, Object?>>> slices(
    String viewer, {
    required DateTime now,
    Map<String, ({String text, DateTime? setAt})> manualLines = const {},
  }) => plan.slicesFor(
    viewerId: viewer,
    beaconIds: [_open, _closed, _empty, 'Bplanslice_missing'],
    manualLines: manualLines,
    now: now,
  );

  test('repository reads every Request in one call, absent ones '
      'skipped', () async {
    await save(_open, [_s(_a, who: _helper, startMin: 0)]);
    final sources = await BeaconPlanRepository(
      database,
    ).sliceSourcesFor(_helper, [_open, _closed, _empty, 'Bplanslice_missing']);
    expect(sources.keys.toSet(), {_open, _closed, _empty});
    expect(sources[_open]!.steps.single.id, _a);
    expect(sources[_open]!.steps.single.startAt, _t0);
    expect(sources[_open]!.steps.single.description, 'About $_a');
    expect(sources[_open]!.pendingFromSeq, 1);
    expect(sources[_open]!.pendingRevisions.single.seq, 1);
    expect(sources[_empty]!.steps, isEmpty);
  });

  test('current, next, pending change and NOW for the assignee', () async {
    await save(_open, [
      _s(_a, who: _helper, startMin: 0, endMin: 60),
      _s(_b, who: _member, startMin: 30),
      _s(_c, who: _helper, startMin: 120),
    ]);
    final all = await slices(
      _helper,
      now: _t0.add(const Duration(minutes: 40)),
    );
    expect(all.keys, [_open], reason: 'no steps, no slice');
    final slice = all[_open]!;
    expect(slice['done'], 0);
    expect(slice['total'], 3);
    expect(slice['overdueMine'], 0);
    final current = slice['current']! as Map<String, Object?>;
    expect(current['stepId'], _a);
    expect(current['description'], 'About $_a');
    expect(current['startAt'], '2030-01-10T09:00:00.000Z');
    expect(current['endAt'], '2030-01-10T10:00:00.000Z');
    expect(current['overdueSince'], isNull);
    expect((slice['next']! as Map)['stepId'], _c);
    expect(slice['alsoActive'], isEmpty);

    final pending = slice['pendingAck']! as Map<String, Object?>;
    expect(pending['fromSeq'], 1);
    expect(pending['headSeq'], 1);
    expect(pending['changeCount'], 2);
    expect(pending['actorIds'], [_author]);
    expect(pending['actorNames'], {_author: _author});
    expect((pending['stepIds']! as List).toSet(), {_a, _c});
    expect((pending['sample']! as Map)['op'], 'added');

    final now = slice['now']! as Map<String, Object?>;
    expect(now['source'], 'plan');
    expect(now['stepId'], _b, reason: 'the step that started last');
    expect(now['assigneeId'], _member);
    expect(now['index'], 2);
    expect(now['count'], 3);
  });

  test('attachSlices fills planSliceJson on readable inbox rows only and '
      'drops the internal set-at key', () async {
    await save(_open, [_s(_a, who: _helper, startMin: 0)]);
    final rows = await plan.attachSlices(
      viewerId: _helper,
      setAtKey: '_setAt',
      rows: [
        {
          'beaconId': _open,
          'isRoomMember': true,
          'currentLine': '',
          '_setAt': null,
          'planSliceJson': null,
        },
        {'beaconId': _closed, 'isRoomMember': false, 'planSliceJson': null},
      ],
    );
    expect(rows.first.containsKey('_setAt'), isFalse);
    final slice = jsonDecode(rows.first['planSliceJson']! as String) as Map;
    expect(slice['total'], 1);
    expect(rows.last['planSliceJson'], isNull);
  });

  test('a newer manual NOW line wins over the plan', () async {
    await save(_open, [_s(_a, who: _helper, startMin: 0)]);
    final slice = (await slices(
      _helper,
      now: _t0.add(const Duration(minutes: 5)),
      manualLines: {
        _open: (
          text: 'Doors open',
          setAt: _t0.add(const Duration(minutes: 1)),
        ),
      },
    ))[_open]!;
    expect(slice['now'], isNull);
  });

  test('overdue step and «Понятно» clearing the pending change', () async {
    await save(_open, [_s(_a, who: _helper, startMin: 0, endMin: 30)]);
    await plan.ack(actorId: _helper, beaconId: _open, uptoSeq: 1);
    final slice = (await slices(
      _helper,
      now: _t0.add(const Duration(minutes: 45)),
    ))[_open]!;
    expect(slice['pendingAck'], isNull);
    expect(slice['overdueMine'], 1);
    final current = slice['current']! as Map<String, Object?>;
    expect(current['overdueSince'], '2030-01-10T09:30:00.000Z');
  });

  test('a retime by someone else is sampled with from / to', () async {
    await save(_open, [_s(_a, who: _helper, startMin: 0)]);
    await plan.ack(actorId: _helper, beaconId: _open, uptoSeq: 1);
    await save(_open, [_s(_a, who: _helper, startMin: 60)], base: 1);
    final pending =
        (await slices(_helper, now: _t0))[_open]!['pendingAck']!
            as Map<String, Object?>;
    expect(pending['fromSeq'], 2);
    expect(pending['changeCount'], 1);
    final sample = pending['sample']! as Map<String, Object?>;
    expect(sample['op'], 'retimed');
    expect(sample['stepId'], _a);
    expect(sample['title'], 'Step $_a');
    expect(sample['from'], '2030-01-10T09:00:00.000Z');
    expect(sample['to'], '2030-01-10T10:00:00.000Z');
    expect(
      PlanChange.fromJson(sample).toStartAt,
      _t0.add(const Duration(hours: 1)),
      reason: 'the raw change travels along',
    );
  });

  test('a ticked step leaves current and counts as done', () async {
    await save(_open, [
      _s(_a, who: _helper, startMin: 0),
      _s(_b, who: _helper),
    ]);
    await plan.setDone(actorId: _helper, stepId: _a, done: true);
    final slice = (await slices(
      _helper,
      now: _t0.add(const Duration(minutes: 5)),
    ))[_open]!;
    expect(slice['done'], 1);
    expect(
      (slice['current']! as Map)['stepId'],
      _b,
      reason: 'an untimed step is active once the previous one is done',
    );
  });

  test('a finished Request carries only done / total', () async {
    await save(_closed, [_s(_d, who: _helper, startMin: 0)]);
    await writer.execute(
      "UPDATE public.beacon SET status = 6 WHERE id = '$_closed'",
    );
    final slice = (await slices(
      _helper,
      now: _t0.add(const Duration(minutes: 5)),
    ))[_closed]!;
    expect(slice, {
      'done': 0,
      'total': 1,
      'overdueMine': 0,
      'current': null,
      'alsoActive': isEmpty,
      'next': null,
      'pendingAck': null,
      'now': null,
    });
  });

  test('another viewer sees no pending change of someone else', () async {
    await save(_open, [_s(_a, who: _helper, startMin: 0)]);
    final slice = (await slices(_member, now: _t0))[_open]!;
    expect(slice['pendingAck'], isNull);
    expect(slice['current'], isNull);
    expect(slice['total'], 1);
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
      parameters: {'id': users[i], 'key': pgTestPublicKey('planslice', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_open', '$_author', 'Open', '', 0, now()),
       ('$_closed', '$_author', 'Closed', '', 0, now()),
       ('$_empty', '$_author', 'Empty', '', 0, now())
''');
  var n = 0;
  for (final beacon in [_open, _closed, _empty]) {
    for (final user in [_helper, _member]) {
      await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pplanslice${(n++).toString().padLeft(4, '0')}', '$beacon', '$user', 0, 0, 3)
''');
    }
  }
}
