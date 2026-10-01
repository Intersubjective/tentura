import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_sweep_case.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../../support/build_test_qa_integration_controller.dart';

/// A25: `QaIntegrationController.closureFixture` backs the closure web e2e
/// (`/_qa/integration/closure-fixture`). It is guarded like the other QA
/// actions: 404 when QA auth is disabled, in production, or the token is
/// missing / wrong, and 400 for a missing or malformed `runId`.
void main() {
  Env env({
    String environment = Environment.test,
    bool qaAuthEnabled = true,
  }) => Env(
    environment: environment,
    serverUri: Uri.parse('https://test.tentura.local'),
    qaAuthEnabled: qaAuthEnabled,
    qaAuthToken: 'secret',
  );

  Request request({
    Object? body = const {'runId': 'closure-a1'},
    String? token,
  }) => Request(
    'POST',
    Uri.parse('http://localhost/_qa/integration/closure-fixture').replace(
      queryParameters: {'_qa_token': ?token},
    ),
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  Future<Response> call(Env e, Request r) => buildTestQaIntegrationController(
    env: e,
    closureRepository: _NoClosureRepository(),
    sweep: ClosureFinalizeSweepCase(
      unitOfWork: _Uow(),
      closureRepository: _NoClosureRepository(),
      finalizer: _Finalizer(),
      env: e,
      logger: Logger('QaClosureFixtureTest'),
    ),
  ).closureFixture(r);

  test('QA auth disabled -> 404', () async {
    final r = await call(env(qaAuthEnabled: false), request(token: 'secret'));
    expect(r.statusCode, 404);
  });

  test('production -> 404', () async {
    final r = await call(
      env(environment: Environment.prod),
      request(token: 'secret'),
    );
    expect(r.statusCode, 404);
  });

  test('wrong token -> 404', () async {
    final r = await call(env(), request(token: 'nope'));
    expect(r.statusCode, 404);
  });

  test('missing runId -> 400', () async {
    final r = await call(env(), request(body: const {}, token: 'secret'));
    expect(r.statusCode, 400);
  });
}

class _NoClosureRepository implements ClosureRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('closure repository must not be touched');
}

class _Uow implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) => action();
}

class _Finalizer implements ClosureFinalizerPort {
  @override
  Future<void> finalize({
    required String beaconId,
    required int epoch,
    required FinalizeReason reason,
  }) async {}
}
