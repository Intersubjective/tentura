@Tags(['pg', 'repo-files'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import 'constellation_received_request_provenance_pg_test.dart' as provenance;

/// Keep the real provenance suite behind a held lifecycle lock until its own
/// provisioning backend is observed waiting. Test bodies retain their normal
/// behaviour budget; provisioning belongs in suite setup.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARDED_FIELD_CONTENTION_TEST_DB',
    defaultNamePrefix: 'tentura_test_forwarded_contention',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
  }

  final release = Completer<void>();
  final provisioningBackend = Completer<int>();
  final stop = Completer<void>();
  Future<void>? holding;
  Future<void>? watching;
  (Object, StackTrace)? failure;

  Future<void> observeProvisioning() async {
    final pid = await Future.any<int?>([
      provisioningBackend.future,
      stop.future.then((_) => null),
    ]);
    if (pid == null) return;
    final observer = await Connection.open(
      target.adminEnv.pgEndpoint,
      settings: ConnectionSettings(
        sslMode: target.adminEnv.pgEndpointSettings.sslMode,
        queryTimeout: const Duration(seconds: 2),
      ),
    );
    try {
      while (!stop.isCompleted) {
        final rows = await observer.execute(
          Sql.named('''
SELECT EXISTS (
  SELECT 1 FROM pg_locks
  WHERE pid = @pid AND NOT granted AND locktype = 'advisory'
    AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
    AND classid::bigint = ((hashtext(@key)::bigint >> 32) & 4294967295)
    AND objid::bigint = (hashtext(@key)::bigint & 4294967295)
    AND objsubid = 1
)
'''),
          parameters: {'pid': pid, 'key': 'tentura_disposable_pg_lifecycle'},
        );
        if (rows.single.single == true) {
          release.complete();
          return;
        }
      }
    } finally {
      await observer.close();
    }
  }

  setUpAll(() async {
    final acquired = Completer<void>();
    final pending = withDisposablePgLifecycleLock(target.adminEnv, () async {
      acquired.complete();
      await release.future;
    });
    final held = pending.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        failure = (error, stack);
      },
    );
    holding = held;
    await Future.any([acquired.future, held]);
    expect(
      acquired.isCompleted,
      isTrue,
      reason: 'Lifecycle lock acquisition failed',
    );
    watching = observeProvisioning()
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw StateError(
            'Provenance provisioning never queued on the lifecycle lock',
          ),
        )
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            failure = (error, stack);
            if (!stop.isCompleted) stop.complete();
            if (!release.isCompleted) release.completeError(error, stack);
          },
        );
  });
  setUp(() {
    expect(failure, isNull);
    expect(
      release.isCompleted,
      isTrue,
      reason:
          'A provenance body started before provisioning contention released the lock',
    );
  });
  tearDownAll(() async {
    if (!stop.isCompleted) stop.complete();
    if (!release.isCompleted) release.complete();
    await watching;
    await holding;
    final error = failure;
    if (error != null) Error.throwWithStackTrace(error.$1, error.$2);
  });

  group(
    'with competing database provisioning',
    () => provenance.main(
      onProvisioningBackend: provisioningBackend.complete,
    ),
  );
}
