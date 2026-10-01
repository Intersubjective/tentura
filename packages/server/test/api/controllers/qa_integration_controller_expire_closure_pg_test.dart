@Tags(['pg'])
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_sweep_case.dart';
import 'package:tentura_server/domain/use_case/trust_publisher_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/build_test_qa_integration_controller.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/recording_beacon_hierarchy_outbox.dart';

/// A24a: `QaIntegrationController.expireClosure` against Postgres.
///
/// The action must move the live evaluating epoch's `closes_at` into the past
/// and then run the *real* `ClosureFinalizeSweepCase` once — a not-yet-due
/// epoch ends up finalized (reason `expired`) with the request closed, and
/// only the requested request is affected.

const _author = 'Uqaexpauth01';
const _helper = 'Uqaexphelp001';
const _beacon = 'Bqaexpbeacon1';
const _otherBeacon = 'Bqaexpbeacon2';
const _users = [_author, _helper];
const _qaToken = 'secret';

const _done = 1;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_QA_EXPIRE_CLOSURE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_qa_expire_closure',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;
  late ClosureRepository repo;
  late MutatingUnitOfWork uow;
  late Env env;

  Future<void> sql(String s) => writer.execute(s);

  Future<List<List<Object?>>> rows(String s) async =>
      (await writer.execute(s)).map((r) => r.toList()).toList();

  Future<void> seedRequest(String beaconId) async {
    await sql('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$beaconId', '$_author', 'qa expire closure', '',
        ${BeaconStatus.reviewOpen.smallintValue}, now())
''');
    // Evaluating epoch with 6 days left: not due, so only the QA action can
    // make the sweep pick it up.
    await sql('''
INSERT INTO public.beacon_closure (beacon_id, epoch, status, opened_at, closes_at)
VALUES ('$beaconId', 1, 0, now() - interval '1 day', now() + interval '6 days')
''');
    await sql('''
INSERT INTO public.beacon_closure_member
  (beacon_id, epoch, user_id, departure, active_at_open)
VALUES ('$beaconId', 1, '$_helper', NULL, true)
''');
    await sql('''
INSERT INTO public.beacon_closure_outcome (beacon_id, helper_id, outcome)
VALUES ('$beaconId', '$_helper', $_done)
''');
  }

  Future<int> epochStatus(String beaconId) async {
    final r = await rows('''
SELECT status FROM public.beacon_closure
WHERE beacon_id = '$beaconId' AND epoch = 1
''');
    return r.single.single! as int;
  }

  Future<int> beaconStatus(String beaconId) async {
    final r = await rows(
      "SELECT status FROM public.beacon WHERE id = '$beaconId'",
    );
    return r.single.single! as int;
  }

  Future<bool> closesInThePast(String beaconId) async {
    final r = await rows('''
SELECT closes_at < now() FROM public.beacon_closure
WHERE beacon_id = '$beaconId' AND epoch = 1
''');
    return r.single.single! as bool;
  }

  Request request({
    required Map<String, Object?> body,
    String? queryToken = _qaToken,
  }) => Request(
    'POST',
    Uri.parse('http://localhost/_qa/integration/expire-closure').replace(
      queryParameters: {'_qa_token': ?queryToken},
    ),
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  Future<Response> expire({
    required Env controllerEnv,
    required Request request,
    Future<void> Function()? afterSelect,
  }) {
    final outbox = RecordingBeaconHierarchyOutbox();
    final publisher = TrustPublisherCase(
      TrustPublishRepository(db),
      env: env,
      logger: Logger('QaExpireClosurePgTestPublisher'),
    );
    final finalizer = ClosureFinalizeCase(
      unitOfWork: uow,
      closureRepository: repo,
      beaconRepository: BeaconRepository(db),
      trustLedger: TrustLedgerRepository(db),
      lifecycleEffects: buildLifecycleEffectsCase(outbox: outbox),
      attentionSystemSettlement: AttentionSystemSettlementRepository(db),
      trustPublisher: publisher,
      env: env,
      logger: Logger('QaExpireClosurePgTestFinalizer'),
    );
    final sweep = ClosureFinalizeSweepCase(
      unitOfWork: uow,
      closureRepository: repo,
      finalizer: finalizer,
      env: env,
      logger: Logger('QaExpireClosurePgTestSweep'),
    )..afterSelect = afterSelect;
    return buildTestQaIntegrationController(
      env: controllerEnv,
      closureRepository: repo,
      sweep: sweep,
    ).expireClosure(request);
  }

  Env qaEnv({
    String environment = Environment.test,
    bool qaAuthEnabled = true,
  }) => Env(
    environment: environment,
    serverUri: Uri.parse('https://test.tentura.local'),
    qaAuthEnabled: qaAuthEnabled,
    qaAuthToken: _qaToken,
  );

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      db = TenturaDb(target.databaseEnv);
      repo = ClosureRepository(db);
      uow = MutatingUnitOfWork(db);
      env = Env(environment: Environment.test);
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
    });

    setUp(() async {
      await sql('''
TRUNCATE public.beacon_closure_result, public.beacon_closure_member,
  public.beacon_closure, public.beacon_closure_outcome,
  public.beacon_closure_author_split, public.beacon_closure_support,
  public.beacon_closure_commit, public.beacon_closure_mark,
  public.beacon_closure_story, public.trust_evidence,
  public.trust_publish_queue, public.user_block
CASCADE
''');
      await sql('DELETE FROM public.user_trust_edge');
      await sql(
        "DELETE FROM public.beacon WHERE id IN ('$_beacon', '$_otherBeacon')",
      );
      await sql(
        "UPDATE public.trust_cutover_state SET status = 'done' WHERE id = 1",
      );
      for (var i = 0; i < _users.length; i++) {
        await sql('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('${_users[i]}', '${_users[i]}', '${pgTestPublicKey('qaexp', i + 1)}')
ON CONFLICT (id) DO NOTHING
''');
      }
      await seedRequest(_beacon);
    });
  }

  test(
    'enabled: a not-yet-due epoch is finalized by the real sweep',
    () async {
      expect(await epochStatus(_beacon), 0);
      expect(await closesInThePast(_beacon), isFalse);

      // `afterSelect` fires once per `ClosureFinalizeSweepCase.run()`, between
      // the due-epoch select and the per-row lock. The epoch is still
      // evaluating there, so this observes the action's `closes_at` move
      // (made before the sweep) without finalize overwriting it, and proves
      // the real sweep ran rather than a direct finalize.
      var sweepRuns = 0;
      bool? evaluatingAtSelect;
      bool? deadlinePassedAtSelect;
      bool? deadlineJustPassedAtSelect;
      final response = await expire(
        controllerEnv: qaEnv(),
        request: request(body: {'beaconId': _beacon}),
        afterSelect: () async {
          sweepRuns++;
          final r = await rows('''
SELECT status = 0, closes_at <= now(),
       closes_at >= now() - interval '1 minute'
FROM public.beacon_closure WHERE beacon_id = '$_beacon' AND epoch = 1
''');
          evaluatingAtSelect = r.single[0]! as bool;
          deadlinePassedAtSelect = r.single[1]! as bool;
          deadlineJustPassedAtSelect = r.single[2]! as bool;
        },
      );

      expect(response.statusCode, 200);
      expect(sweepRuns, 1, reason: 'exactly one real sweep pass');
      expect(evaluatingAtSelect, isTrue, reason: 'still evaluating at select');
      expect(deadlinePassedAtSelect, isTrue, reason: 'closes_at in the past');
      expect(
        deadlineJustPassedAtSelect,
        isTrue,
        reason: 'closes_at = now() - 1 second, not an arbitrary old date',
      );

      expect(await epochStatus(_beacon), 1);
      expect(await beaconStatus(_beacon), BeaconStatus.closed.smallintValue);
      final reason = await rows('''
SELECT finalize_reason, finalized_at IS NOT NULL
FROM public.beacon_closure WHERE beacon_id = '$_beacon' AND epoch = 1
''');
      expect(reason.single, [FinalizeReason.expired.dbValue, true]);
      final results = await rows('''
SELECT count(*)::int FROM public.beacon_closure_result
WHERE beacon_id = '$_beacon'
''');
      expect(results.single.single, greaterThan(0));
    },
    skip: skipReason,
  );

  test(
    'enabled: only the requested request is expired',
    () async {
      await seedRequest(_otherBeacon);
      Future<Object?> closesAtOf(String id) async => (await rows(
        'SELECT closes_at FROM public.beacon_closure '
        "WHERE beacon_id = '$id' AND epoch = 1",
      )).single.single;
      final otherClosesAtBefore = await closesAtOf(_otherBeacon);
      final targetClosesAtBefore = await closesAtOf(_beacon);
      expect(otherClosesAtBefore, isNotNull);

      // Checked inside the sweep (before any finalize can touch the rows):
      // the supplied request's deadline moved, the other one's did not.
      Object? otherClosesAtAtSelect;
      Object? targetClosesAtAtSelect;
      final response = await expire(
        controllerEnv: qaEnv(),
        request: request(body: {'beaconId': _beacon}),
        afterSelect: () async {
          otherClosesAtAtSelect = await closesAtOf(_otherBeacon);
          targetClosesAtAtSelect = await closesAtOf(_beacon);
        },
      );

      expect(response.statusCode, 200);
      expect(targetClosesAtAtSelect, isNot(targetClosesAtBefore));
      expect(otherClosesAtAtSelect, otherClosesAtBefore);
      expect(await closesAtOf(_otherBeacon), otherClosesAtBefore);
      expect(await epochStatus(_beacon), 1);
      expect(await epochStatus(_otherBeacon), 0);
      expect(await closesInThePast(_otherBeacon), isFalse);
      expect(
        await beaconStatus(_otherBeacon),
        BeaconStatus.reviewOpen.smallintValue,
      );
    },
    skip: skipReason,
  );

  test(
    'QA auth disabled: rejected and the epoch is left untouched',
    () async {
      var sweepRuns = 0;
      final response = await expire(
        controllerEnv: qaEnv(qaAuthEnabled: false),
        request: request(body: {'beaconId': _beacon}),
        afterSelect: () async => sweepRuns++,
      );

      expect(response.statusCode, 404);
      expect(sweepRuns, 0, reason: 'sweep not run');
      expect(await epochStatus(_beacon), 0);
      expect(await closesInThePast(_beacon), isFalse);
      expect(
        await beaconStatus(_beacon),
        BeaconStatus.reviewOpen.smallintValue,
      );
    },
    skip: skipReason,
  );

  test(
    'production config: rejected and the epoch is left untouched',
    () async {
      var sweepRuns = 0;
      final response = await expire(
        controllerEnv: qaEnv(environment: Environment.prod),
        request: request(body: {'beaconId': _beacon}),
        afterSelect: () async => sweepRuns++,
      );

      expect(response.statusCode, 404);
      expect(sweepRuns, 0, reason: 'sweep not run');
      expect(await epochStatus(_beacon), 0);
      expect(await closesInThePast(_beacon), isFalse);
      expect(
        await beaconStatus(_beacon),
        BeaconStatus.reviewOpen.smallintValue,
      );
    },
    skip: skipReason,
  );

  test(
    'wrong QA token: rejected and the epoch is left untouched',
    () async {
      var sweepRuns = 0;
      final response = await expire(
        controllerEnv: qaEnv(),
        request: request(body: {'beaconId': _beacon}, queryToken: 'wrong'),
        afterSelect: () async => sweepRuns++,
      );

      expect(response.statusCode, 404);
      expect(sweepRuns, 0, reason: 'sweep not run');
      expect(await epochStatus(_beacon), 0);
      expect(await closesInThePast(_beacon), isFalse);
    },
    skip: skipReason,
  );
}
