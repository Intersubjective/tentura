@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/plan/plan.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_plan_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/entity/beacon_plan.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/beacon_plan_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/plan_cases.dart';

const _author = 'Uplancase_au1';
const _helper = 'Uplancase_hl1';
const _member = 'Uplancase_mb1';
const _outsider = 'Uplancase_ou1';

const _request = 'Bplancase_rq1';
const _closed = 'Bplancase_cl1';
const _copy = 'Bplancase_cp1';

const _a = 'PS00000000000a';
const _b = 'PS00000000000b';
const _c = 'PS00000000000c';

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
  assigneeId: who,
  startAt: startMin == null ? null : _t0.add(Duration(minutes: startMin)),
  endAt: endMin == null ? null : _t0.add(Duration(minutes: endMin)),
);

String _json(List<PlanStepSnapshot> steps) => PlanSnapshot(steps).encode();

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_PLAN_CASE_TEST_DB',
    defaultNamePrefix: 'tentura_test_beacon_plan_case',
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
    plan = _buildCase(database, target.databaseEnv);
  });

  setUp(() => _resetFixture(writer));

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  Future<Map<String, Object?>> view([String viewer = _author]) =>
      plan.view(beaconId: _request, viewerId: viewer);

  Future<PlanSaveOutcome> save(
    List<PlanStepSnapshot> steps, {
    int base = 0,
    String actor = _author,
  }) => plan.save(
    actorId: actor,
    beaconId: _request,
    baseSeq: base,
    stepsJson: _json(steps),
  );

  test(
    'first save writes revision 1, steps, a chat line and pending',
    () async {
      final outcome = await save([
        _s(_a, who: _helper, startMin: 0),
        _s(_b, who: _member),
      ]);
      expect(outcome.kind, PlanSaveOutcomeKind.applied);
      expect(outcome.revisionSeq, 1);

      final v = await view();
      expect(v['revisionSeq'], 1);
      final steps = (v['steps']! as List).cast<Map<String, Object?>>();
      expect(steps.map((s) => s['id']), [_a, _b]);
      expect(steps.first['assigneeId'], _helper);
      expect(steps.first['startAt'], '2030-01-10T09:00:00.000Z');

      final line = await writer.execute('''
SELECT semantic_marker, system_message_kind, author_id
FROM public.beacon_room_message WHERE beacon_id = '$_request'
''');
      expect(line.single.toList(), [
        BeaconRoomSemanticMarker.planRevised,
        5,
        _author,
      ]);
      final pending = await writer.execute('''
SELECT user_id, pending_from_seq FROM public.beacon_plan_member
WHERE beacon_id = '$_request' ORDER BY user_id
''');
      expect(pending.map((r) => r.toList()), [
        [_helper, 1],
        [_member, 1],
      ]);
    },
  );

  test('saving the same plan again is a no-op', () async {
    await save([_s(_a)]);
    final again = await save([_s(_a)], base: 1);
    expect(again.kind, PlanSaveOutcomeKind.noop);
    expect(again.revisionSeq, 1);
  });

  test('concurrent edits of different steps merge', () async {
    await save([_s(_a), _s(_b)]);
    await save([_s(_a, title: 'A by author'), _s(_b)], base: 1);
    final merged = await save(
      [_s(_a), _s(_b, title: 'B by helper')],
      base: 1,
      actor: _helper,
    );
    expect(merged.kind, PlanSaveOutcomeKind.merged);
    expect(merged.revisionSeq, 3);
    expect(merged.theirStepIds, {_a});
    expect(merged.theirActorIds, {_author});
    final steps = ((await view())['steps']! as List)
        .cast<Map<String, Object?>>();
    expect(steps.map((s) => s['title']), ['A by author', 'B by helper']);
  });

  test(
    'concurrent edits of the same step conflict and write nothing',
    () async {
      await save([_s(_a), _s(_b)]);
      await save([_s(_a, title: 'x'), _s(_b)], base: 1);
      await expectLater(
        save([_s(_a, title: 'y'), _s(_b)], base: 1, actor: _helper),
        throwsA(
          isA<PlanEditConflictException>()
              .having((e) => e.currentSeq, 'currentSeq', 2)
              .having((e) => e.conflictStepIds, 'ids', [_a]),
        ),
      );
      expect((await view())['revisionSeq'], 2);
    },
  );

  test('a step can only go to an admitted person', () async {
    await expectLater(
      save([_s(_a, who: _outsider)]),
      throwsA(isA<PlanAssigneeNotAdmittedException>()),
    );
  });

  test('outsiders can neither read nor write', () async {
    await expectLater(view(_outsider), throwsA(isA<UnauthorizedException>()));
    await expectLater(
      save([_s(_a)], actor: _outsider),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('a closed Request plan is read-only', () async {
    await expectLater(
      plan.save(
        actorId: _author,
        beaconId: _closed,
        baseSeq: 0,
        stepsJson: _json([_s(_c)]),
      ),
      throwsA(isA<PlanNotEditableException>()),
    );
  });

  test('ticks coalesce into one line; untick strikes the entry', () async {
    await save([_s(_a, who: _helper), _s(_b, who: _member)]);
    await plan.setDone(actorId: _helper, stepId: _a, done: true);
    await plan.setDone(actorId: _member, stepId: _b, done: true);
    final lines = await writer.execute('''
SELECT system_payload::text FROM public.beacon_room_message
WHERE beacon_id = '$_request'
  AND semantic_marker = ${BeaconRoomSemanticMarker.planStepsDone}
''');
    expect(lines, hasLength(1));
    final ticks =
        (jsonDecode(lines.single[0]! as String) as Map)['ticks'] as List;
    expect(ticks.map((t) => (t as Map)['stepId']), [_a, _b]);

    await plan.setDone(actorId: _author, stepId: _a, done: false);
    final after = await writer.execute('''
SELECT system_payload::text FROM public.beacon_room_message
WHERE beacon_id = '$_request'
  AND semantic_marker = ${BeaconRoomSemanticMarker.planStepsDone}
''');
    final first =
        ((jsonDecode(after.single[0]! as String) as Map)['ticks'] as List).first
            as Map;
    expect(first['undoneById'], _author);
    final steps = ((await view())['steps']! as List)
        .cast<Map<String, Object?>>();
    expect(steps.first['doneAt'], isNull);
    expect(steps.last['doneById'], _member);
  });

  test('ticks never enter revisions', () async {
    await save([_s(_a, who: _helper)]);
    await plan.setDone(actorId: _helper, stepId: _a, done: true);
    expect((await view())['revisionSeq'], 1);
  });

  test('ack clears pending up to the head; later changes re-open it', () async {
    await save([_s(_a, who: _helper, startMin: 0)]);
    await plan.ack(actorId: _helper, beaconId: _request, uptoSeq: 1);
    var member = await _member_(writer, _helper);
    expect(member['pending_from_seq'], isNull);
    expect(member['acked_seq'], 1);

    await save([_s(_a, who: _helper, startMin: 30)], base: 1);
    member = await _member_(writer, _helper);
    expect(member['pending_from_seq'], 2);
    final pending = (await view(_helper))['viewerPending']! as Map;
    expect((pending['changes']! as List).single, containsPair('op', 'retimed'));

    // A description-only edit needs no confirmation.
    await plan.ack(actorId: _helper, beaconId: _request, uptoSeq: 2);
    await plan.save(
      actorId: _author,
      beaconId: _request,
      baseSeq: 2,
      stepsJson: PlanSnapshot([
        _s(_a, who: _helper, startMin: 30).copyWith(description: 'more'),
      ]).encode(),
    );
    member = await _member_(writer, _helper);
    expect(member['pending_from_seq'], isNull);
  });

  test('cant make: reschedule moves the step and writes marker 15', () async {
    await save([_s(_a, who: _helper, startMin: 0)]);
    final outcome = await plan.cantMake(
      actorId: _helper,
      stepId: _a,
      option: PlanCantMakeOption.reschedule,
      baseSeq: 1,
      newStartAt: _t0.add(const Duration(hours: 1)),
    );
    expect(outcome.revisionSeq, 2);
    final steps = ((await view())['steps']! as List)
        .cast<Map<String, Object?>>();
    expect(steps.single['startAt'], '2030-01-10T10:00:00.000Z');
    final markers = await writer.execute('''
SELECT semantic_marker FROM public.beacon_room_message
WHERE beacon_id = '$_request' ORDER BY created_at
''');
    expect(markers.map((r) => r[0]), [
      BeaconRoomSemanticMarker.planRevised,
      BeaconRoomSemanticMarker.planCantMake,
    ]);
  });

  test(
    'cant make: handover needs an admitted person and the assignee',
    () async {
      await save([_s(_a, who: _helper)]);
      await expectLater(
        plan.cantMake(
          actorId: _member,
          stepId: _a,
          option: PlanCantMakeOption.handover,
          baseSeq: 1,
          toUserId: _member,
        ),
        throwsA(isA<PlanActionStaleException>()),
      );
      await expectLater(
        plan.cantMake(
          actorId: _helper,
          stepId: _a,
          option: PlanCantMakeOption.handover,
          baseSeq: 1,
          toUserId: _outsider,
        ),
        throwsA(isA<PlanAssigneeNotAdmittedException>()),
      );
      await plan.cantMake(
        actorId: _helper,
        stepId: _a,
        option: PlanCantMakeOption.handover,
        baseSeq: 1,
        toUserId: _member,
      );
      expect((await _member_(writer, _member))['pending_from_seq'], 2);
    },
  );

  test('cant make: chat writes no revision and leaves the counter, so a '
      'concurrent save and restore still apply', () async {
    await save([_s(_a, who: _helper), _s(_b)]);
    final outcome = await plan.cantMake(
      actorId: _helper,
      stepId: _a,
      option: PlanCantMakeOption.chat,
      baseSeq: 1,
      excerpt: 'Stuck in traffic',
    );
    expect(outcome.revisionSeq, 1);
    expect((await view())['revisionSeq'], 1);
    final revisions = await writer.execute('''
SELECT count(*)::int FROM public.beacon_plan_revision
WHERE beacon_id = '$_request'
''');
    expect(revisions.single[0], 1);
    expect((await _member_(writer, _helper))['pending_from_seq'], isNull);
    final activity = await writer.execute('''
SELECT diff->>'option' FROM public.beacon_activity_event
WHERE beacon_id = '$_request' AND type = ${BeaconActivityEventTypeBits.planCantMake}
''');
    expect(activity.single[0], PlanCantMakeOption.chat);

    final saved = await save([_s(_a, who: _helper)], base: 1);
    expect(saved.kind, PlanSaveOutcomeKind.applied);
    expect(saved.revisionSeq, 2);
    final restored = await plan.restore(
      actorId: _author,
      beaconId: _request,
      fromSeq: 1,
      baseSeq: 2,
    );
    expect(restored.revisionSeq, 3);
  });

  test('a malformed draft is invalid, not too large', () async {
    // The draft is checked before any I/O: the call itself throws.
    expect(
      () => plan.save(
        actorId: _author,
        beaconId: _request,
        baseSeq: 0,
        stepsJson: '{not json',
      ),
      throwsA(isA<PlanInvalidException>()),
    );
    expect(
      () => save([_s(_a), _s(_a)]),
      throwsA(isA<PlanInvalidException>()),
    );
  });

  test('restore brings back removed steps with their current ticks', () async {
    await save([_s(_a), _s(_b)]);
    await plan.setDone(actorId: _author, stepId: _b, done: true);
    await save([_s(_a)], base: 1);
    expect((await view())['steps']! as List, hasLength(1));
    final outcome = await plan.restore(
      actorId: _author,
      beaconId: _request,
      fromSeq: 1,
      baseSeq: 2,
    );
    expect(outcome.revisionSeq, 3);
    final steps = ((await view())['steps']! as List)
        .cast<Map<String, Object?>>();
    expect(steps.map((s) => s['id']), [_a, _b]);
    expect(steps.last['doneById'], _author);
    await expectLater(
      plan.restore(
        actorId: _author,
        beaconId: _request,
        fromSeq: 1,
        baseSeq: 2,
      ),
      throwsA(isA<PlanEditConflictException>()),
    );
  });

  test(
    'copy resets assignees and ticks, keeps order and given times',
    () async {
      await save([_s(_a, who: _helper, startMin: 0), _s(_b, who: _member)]);
      await plan.setDone(actorId: _author, stepId: _a, done: true);
      final copied = await database.transaction(
        () => plan.copyPlan(
          actorId: _author,
          sourceBeaconId: _request,
          targetBeaconId: _copy,
          stepTimes: {
            _a: (startAt: _t0.add(const Duration(days: 7)), endAt: null),
          },
        ),
      );
      expect(copied, 2);
      final v = await plan.view(beaconId: _copy, viewerId: _author);
      expect(v['copiedFromBeaconId'], _request);
      final steps = (v['steps']! as List).cast<Map<String, Object?>>();
      expect(steps.map((s) => s['title']), ['Step $_a', 'Step $_b']);
      expect(steps.every((s) => s['assigneeId'] == null), isTrue);
      expect(steps.every((s) => s['doneAt'] == null), isTrue);
      expect(steps.first['startAt'], '2030-01-17T09:00:00.000Z');
      expect(steps.last['startAt'], isNull);
    },
  );

  test('plan steps never fire the per-row coordination_item notify', () async {
    final triggers = await writer.execute('''
SELECT tgname FROM pg_trigger
WHERE tgrelid = 'public.coordination_item'::regclass
  AND tgname LIKE 'coordination_item_entity_notify%'
ORDER BY tgname
''');
    expect(triggers.map((r) => r[0]), [
      'coordination_item_entity_notify_del',
      'coordination_item_entity_notify_ins',
      'coordination_item_entity_notify_upd',
    ]);
  });
}

BeaconPlanCase _buildCase(TenturaDb db, Env env) => PlanCases(db, env).plan;

Future<Map<String, Object?>> _member_(Connection writer, String userId) async {
  final rows = await writer.execute('''
SELECT pending_from_seq, acked_seq FROM public.beacon_plan_member
WHERE beacon_id = '$_request' AND user_id = '$userId'
''');
  final r = rows.single;
  return {'pending_from_seq': r[0], 'acked_seq': r[1]};
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
  final users = [_author, _helper, _member, _outsider];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('plancase', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now()),
       ('$_closed', '$_author', 'Closed', '', 6, now()),
       ('$_copy', '$_author', 'Copy', '', 3, NULL)
''');
  var n = 0;
  for (final beacon in [_request, _closed]) {
    for (final user in [_helper, _member]) {
      await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pplancase${(n++).toString().padLeft(4, '0')}', '$beacon', '$user', 0, 0, 3)
''');
    }
  }
}
