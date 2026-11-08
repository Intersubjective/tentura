import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/qa_integration_controller.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_sweep_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/build_test_qa_integration_controller.dart';
import '../../support/invalid_json_body.dart';

/// Every closure collaborator throws: none may be reached by a request the
/// JSON-body gate (or the validation right after it) rejects.
final class _UntouchedClosureRepository implements ClosureRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('closure repository touched');
}

final class _UntouchedUnitOfWork implements MutatingUnitOfWorkPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unit of work touched');
}

final class _UntouchedFinalizer implements ClosureFinalizerPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('finalizer touched');
}

/// The JSON-body answer of every QA integration action that reads its body
/// through `readJsonObject`, pinned to what main answered before the helper
/// (4f40b9652): 400 `invalid JSON body`. The positive case per action is a
/// valid JSON object that passes the gate and reaches the action's own first
/// validation (unchanged by the refactor).
void main() {
  final env = Env(
    environment: Environment.test,
    serverUri: Uri.parse('https://test.tentura.local'),
    qaAuthEnabled: true,
    qaAuthToken: 'secret',
  );

  late QaIntegrationController controller;

  setUp(() {
    final closureRepository = _UntouchedClosureRepository();
    controller = buildTestQaIntegrationController(
      env: env,
      closureRepository: closureRepository,
      sweep: ClosureFinalizeSweepCase(
        unitOfWork: _UntouchedUnitOfWork(),
        closureRepository: closureRepository,
        finalizer: _UntouchedFinalizer(),
        env: env,
        logger: Logger('QaIntegrationJsonBodyTest'),
      ),
    );
  });

  Request request(String path, String rawBody) => Request(
    'POST',
    Uri.parse('http://localhost/_qa/integration/$path?_qa_token=secret'),
    body: rawBody,
    headers: {'content-type': 'application/json'},
  );

  final actions =
      <
        String,
        ({
          String path,
          Future<Response> Function(QaIntegrationController, Request) call,
          int okStatus,
          String okBody,
        })
      >{
        'bootstrap': (
          path: 'bootstrap',
          call: (c, r) => c.bootstrap(r),
          okStatus: 400,
          okBody: 'runId is required',
        ),
        'witnessFixture': (
          path: 'witness-fixture',
          call: (c, r) => c.witnessFixture(r),
          okStatus: 400,
          okBody: 'runId is required',
        ),
        'closureFixture': (
          path: 'closure-fixture',
          call: (c, r) => c.closureFixture(r),
          okStatus: 400,
          okBody: 'runId is required',
        ),
        'realtimeSocket': (
          path: 'realtime-socket',
          call: (c, r) => c.realtimeSocket(r),
          okStatus: 403,
          okBody: 'user was not issued by QA bootstrap',
        ),
        'expireClosure': (
          path: 'expire-closure',
          call: (c, r) => c.expireClosure(r),
          okStatus: 400,
          okBody: 'beaconId is required',
        ),
      };

  for (final MapEntry(key: name, value: action) in actions.entries) {
    group(name, () {
      kInvalidJsonBodies.forEach((bodyName, rawBody) {
        test('400 invalid JSON body on $bodyName', () async {
          await expectInvalidJsonBody400(
            await action.call(controller, request(action.path, rawBody)),
          );
        });
      });

      test('a JSON object passes the body gate', () async {
        final r = await action.call(controller, request(action.path, '{}'));
        expect(r.statusCode, action.okStatus);
        expect(await r.readAsString(), action.okBody);
      });
    });
  }
}
