@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/plan/plan.dart';
import 'package:tentura_server/api/controllers/push_action_controller.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_plan_repository.dart';
import 'package:tentura_server/data/service/push_action_token_service.dart';
import 'package:tentura_server/domain/plan/push_action.dart';
import 'package:tentura_server/domain/use_case/beacon_plan_case.dart';
import 'package:tentura_server/domain/use_case/push_action_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/plan_cases.dart';

/// `POST /api/v2/push-action` (#220 §5.9): plan push buttons act through the
/// signed token alone, with the same plan writes as the app.
const _author = 'Upushact_au1';
const _helper = 'Upushact_hl1';
const _member = 'Upushact_mb1';

const _request = 'Bpushact_rq1';

const _a = 'PS0000000000aa';
const _b = 'PS0000000000bb';

final _t0 = DateTime.utc(2030, 1, 10, 9);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PUSH_ACTION_TEST_DB',
    defaultNamePrefix: 'tentura_test_push_action',
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
  late PushActionTokenService tokens;
  late PushActionController controller;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    final env = target.databaseEnv;
    plan = PlanCases(database, env).plan;
    tokens = PushActionTokenService(env);
    controller = PushActionController(
      env,
      PushActionCase(
        tokens,
        BeaconPlanRepository(database),
        plan,
        env: env,
        logger: Logger('PushActionControllerPgTest'),
      ),
    );
  });

  setUp(() => _resetFixture(writer));

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  Future<void> save(List<PlanStepSnapshot> steps, {int base = 0}) => plan.save(
    actorId: _author,
    beaconId: _request,
    baseSeq: base,
    stepsJson: PlanSnapshot(steps).encode(),
  );

  PlanStepSnapshot step(String id, String who) => PlanStepSnapshot(
    id: id,
    title: 'Step $id',
    assigneeId: who,
    startAt: _t0,
  );

  Future<({int status, Map<String, Object?> body})> post(Object? body) async {
    final response = await controller.post(
      Request(
        'POST',
        Uri.parse('http://localhost${PushActionController.path}'),
        body: body is String ? body : jsonEncode(body),
      ),
    );
    final text = await response.readAsString();
    return (
      status: response.statusCode,
      body: (jsonDecode(text) as Map).cast<String, Object?>(),
    );
  }

  String doneToken(String stepId, {String account = _helper}) => tokens.sign(
    PushActionClaims(
      accountId: account,
      action: PushAction.done,
      beaconId: _request,
      stepId: stepId,
    ),
  );

  String ackToken(int seq, {String account = _helper}) => tokens.sign(
    PushActionClaims(
      accountId: account,
      action: PushAction.ack,
      beaconId: _request,
      seq: seq,
    ),
  );

  Future<Object?> doneAt(String stepId) async => (await writer.execute(
    "SELECT done_at FROM public.coordination_item WHERE id = '$stepId'",
  )).single.single;

  test('«Готово» ticks the step once, then is idempotent', () async {
    await save([step(_a, _helper)]);

    final first = await post({'token': doneToken(_a)});
    expect(first.status, 200);
    expect(first.body['status'], 'ok');
    expect(await doneAt(_a), isNotNull);

    final again = await post({'token': doneToken(_a)});
    expect(again.status, 200);
    expect(again.body['status'], 'already');
  });

  test('a reassigned step is stale (409 planActionStale)', () async {
    await save([step(_a, _helper)]);
    await save([step(_a, _member)], base: 1);

    final r = await post({'token': doneToken(_a)});
    expect(r.status, 409);
    expect(r.body['code'], 'planActionStale');
    expect(await doneAt(_a), isNull);
  });

  test('a closed Request is stale', () async {
    await save([step(_a, _helper)]);
    await writer.execute(
      "UPDATE public.beacon SET status = 6 WHERE id = '$_request'",
    );

    final r = await post({'token': doneToken(_a)});
    expect(r.status, 409);
    expect(await doneAt(_a), isNull);
  });

  test('forged, expired-looking and foreign tokens are 401', () async {
    await save([step(_a, _helper)]);
    final token = doneToken(_a);
    final forged = '${token.substring(0, token.length - 4)}AAAA';

    expect((await post({'token': forged})).status, 401);
    expect((await post({'token': 'nope'})).status, 401);
    expect(await doneAt(_a), isNull);
  });

  test('a bad body is 400', () async {
    expect((await post('not json')).status, 400);
    expect((await post({'token': ''})).status, 400);
    expect((await post(['x'])).status, 400);
  });

  test('«Понятно» confirms the pending change', () async {
    await save([step(_a, _helper)]);

    final r = await post({'token': ackToken(1)});
    expect(r.status, 200);
    expect(r.body['status'], 'ok');
    final member = (await writer.execute('''
SELECT pending_from_seq, acked_seq FROM public.beacon_plan_member
WHERE beacon_id = '$_request' AND user_id = '$_helper'
''')).single;
    expect(member[0], isNull);
    expect(member[1], 1);

    expect((await post({'token': ackToken(1)})).body['status'], 'already');
  });

  test('«Понятно» for an older change while a newer one waits is '
      'stale', () async {
    await save([step(_a, _helper)]);
    await plan.ack(actorId: _helper, beaconId: _request, uptoSeq: 1);
    await save([step(_a, _helper), step(_b, _helper)], base: 1);
    // A push for revision 1 arrives late: revision 2 now waits.
    await writer.execute('''
UPDATE public.beacon_plan_member SET acked_seq = 0
WHERE beacon_id = '$_request' AND user_id = '$_helper'
''');

    final r = await post({'token': ackToken(1)});
    expect(r.status, 409);
  });

  test('any method but POST is 405', () {
    final r = controller.methodNotAllowed(
      Request('GET', Uri.parse('http://localhost${PushActionController.path}')),
    );
    expect(r.statusCode, 405);
    expect(r.headers['allow'], 'POST');
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
      parameters: {'id': users[i], 'key': pgTestPublicKey('pushact', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
  var n = 0;
  for (final user in [_helper, _member]) {
    await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Ppushact${(n++).toString().padLeft(4, '0')}', '$_request', '$user', 0, 0, 3)
''');
  }
}
