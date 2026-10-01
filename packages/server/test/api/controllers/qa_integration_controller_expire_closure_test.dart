import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_sweep_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/build_test_qa_integration_controller.dart';

/// A24a: `QaIntegrationController.expireClosure` without a database.
///
/// Guard: same as the other QA actions (404 without advertising the endpoint)
/// for QA auth disabled, production, missing / wrong / empty token; in every
/// rejected or invalid case the closure repository, the unit of work and the
/// finalizer see no call at all.
///
/// Enabled: the action must run the real `ClosureFinalizeSweepCase` exactly
/// once — observable as one `dueEpochs()` select plus the sweep's own
/// per-row lock + `finalize(..., expired)` — and must not finalize anything
/// itself.
void main() {
  const beaconId = 'Bqaexpire0001';

  late _RecordingClosureRepository closureRepository;
  late _RecordingUnitOfWork unitOfWork;
  late _RecordingFinalizer finalizer;
  late ClosureFinalizeSweepCase sweep;
  late int sweepRuns;

  Env env({
    String environment = Environment.test,
    bool qaAuthEnabled = true,
    String qaAuthToken = 'secret',
  }) => Env(
    environment: environment,
    serverUri: Uri.parse('https://test.tentura.local'),
    qaAuthEnabled: qaAuthEnabled,
    qaAuthToken: qaAuthToken,
  );

  Request request({
    Object? body = const {'beaconId': beaconId},
    String? queryToken = 'secret',
    String? authorization,
  }) => Request(
    'POST',
    Uri.parse('http://localhost/_qa/integration/expire-closure').replace(
      queryParameters: {'_qa_token': ?queryToken},
    ),
    body: body is String ? body : jsonEncode(body),
    headers: {
      'content-type': 'application/json',
      'authorization': ?authorization,
    },
  );

  Future<Response> call(Env e, Request r) => buildTestQaIntegrationController(
    env: e,
    closureRepository: closureRepository,
    sweep: sweep,
  ).expireClosure(r);

  void expectNothingHappened() {
    expect(closureRepository.calls, isEmpty, reason: 'repository untouched');
    expect(unitOfWork.runs, 0, reason: 'no transaction opened');
    expect(finalizer.calls, isEmpty, reason: 'nothing finalized');
    expect(sweepRuns, 0, reason: 'sweep not run');
  }

  setUp(() {
    closureRepository = _RecordingClosureRepository(
      due: const [ClosureDueEpoch(beaconId: beaconId, epoch: 1)],
    );
    unitOfWork = _RecordingUnitOfWork();
    finalizer = _RecordingFinalizer();
    sweepRuns = 0;
    sweep = ClosureFinalizeSweepCase(
      unitOfWork: unitOfWork,
      closureRepository: closureRepository,
      finalizer: finalizer,
      env: env(),
      logger: Logger('QaExpireClosureUnitTest'),
    )..afterSelect = () async => sweepRuns++;
  });

  test('is rejected when QA auth is not enabled', () async {
    final response = await call(env(qaAuthEnabled: false), request());

    expect(response.statusCode, 404);
    expectNothingHappened();
  });

  test('is rejected in production even with valid QA configuration', () async {
    final response = await call(env(environment: Environment.prod), request());

    expect(response.statusCode, 404);
    expectNothingHappened();
  });

  test('is rejected without a QA token', () async {
    final response = await call(env(), request(queryToken: null));

    expect(response.statusCode, 404);
    expectNothingHappened();
  });

  test('is rejected with a wrong token', () async {
    final response = await call(env(), request(queryToken: 'wrong'));

    expect(response.statusCode, 404);
    expectNothingHappened();
  });

  test('is rejected when the QA token is empty on both sides', () async {
    final response = await call(
      env(qaAuthToken: ''),
      request(queryToken: ''),
    );

    expect(response.statusCode, 404);
    expectNothingHappened();
  });

  test('enabled: rejects an invalid JSON body without sweeping', () async {
    final response = await call(env(), request(body: 'not-json'));

    expect(response.statusCode, 400);
    expectNothingHappened();
  });

  test('enabled: requires a beaconId without sweeping', () async {
    final response = await call(env(), request(body: {'beaconId': '  '}));

    expect(response.statusCode, 400);
    expectNothingHappened();
  });

  test('enabled: accepts a bearer token', () async {
    final response = await call(
      env(),
      request(queryToken: null, authorization: 'Bearer secret'),
    );

    expect(response.statusCode, 200);
    expect(sweepRuns, 1);
  });

  test('enabled: runs exactly one real sweep pass', () async {
    final response = await call(env(), request());

    expect(response.statusCode, 200);

    // One sweep pass: one candidate select, the hook between select and
    // locks fired once, then the sweep's own per-row work.
    expect(closureRepository.dueEpochsCalls, 1);
    expect(sweepRuns, 1);
    expect(unitOfWork.runs, 1, reason: 'sweep opens one tx per due row');
    expect(closureRepository.lockedRequests, [beaconId]);
    expect(finalizer.calls, [
      (beaconId: beaconId, epoch: 1, reason: FinalizeReason.expired),
    ], reason: 'finalized only by the sweep, once, as expired');
  });

  test('enabled: the sweep is not replaced by a direct finalize', () async {
    // Nothing is due: the action must not finalize on its own account.
    closureRepository.due = const [];

    final response = await call(env(), request());

    expect(response.statusCode, 200);
    expect(closureRepository.dueEpochsCalls, 1);
    expect(sweepRuns, 1);
    expect(finalizer.calls, isEmpty);
    expect(unitOfWork.runs, 0);
  });
}

/// Records every call. `dueEpochs` / `lockRequest` / `liveEpoch` are explicit;
/// any other port method (the new "move `closes_at` into the past" mutator the
/// action uses) is accepted and completes with `Future<void>`.
class _RecordingClosureRepository implements ClosureRepositoryPort {
  _RecordingClosureRepository({required this.due});

  List<ClosureDueEpoch> due;
  final calls = <String>[];
  final lockedRequests = <String>[];
  int dueEpochsCalls = 0;

  @override
  Future<List<ClosureDueEpoch>> dueEpochs({int limit = 50}) async {
    calls.add('dueEpochs');
    dueEpochsCalls++;
    return due;
  }

  @override
  Future<void> lockRequest(String beaconId) async {
    calls.add('lockRequest');
    lockedRequests.add(beaconId);
  }

  @override
  Future<ClosureEpoch?> liveEpoch(String beaconId) async {
    calls.add('liveEpoch');
    return ClosureEpoch(
      beaconId: beaconId,
      epoch: 1,
      status: ClosureEpochStatus.evaluating,
      openedAt: DateTime.utc(2026, 9),
      closesAt: DateTime.utc(2026, 9, 8),
      extensionsUsed: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    return Future<void>.value();
  }
}

class _RecordingUnitOfWork implements MutatingUnitOfWorkPort {
  int runs = 0;

  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) {
    runs++;
    return action();
  }
}

class _RecordingFinalizer implements ClosureFinalizerPort {
  final calls = <({String beaconId, int epoch, FinalizeReason reason})>[];

  @override
  Future<void> finalize({
    required String beaconId,
    required int epoch,
    required FinalizeReason reason,
  }) async {
    calls.add((beaconId: beaconId, epoch: epoch, reason: reason));
  }
}
