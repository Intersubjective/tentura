@Tags(['pg', 'repo-files'])
library;

import 'dart:async';

import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import 'constellation_received_request_provenance_pg_test.dart' as provenance;

/// Run the actual provenance suite while another suite holds the cluster-wide
/// provisioning lock longer than a test's default 30-second behaviour budget.
/// Database provisioning belongs in suite setup, just like the other pg suites;
/// the resolver and its assertions must retain their normal test timeout.
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
  Future<void>? holding;
  Timer? releaseTimer;
  setUpAll(() async {
    final acquired = Completer<void>();
    final pending = withDisposablePgLifecycleLock(target.adminEnv, () async {
      acquired.complete();
      await release.future;
    });
    holding = pending;
    // Propagate connection/lock errors rather than waiting for an acquisition
    // signal that can never arrive.
    await Future.any([acquired.future, pending]);
    releaseTimer = Timer(const Duration(seconds: 35), release.complete);
  });
  tearDownAll(() async {
    releaseTimer?.cancel();
    if (!release.isCompleted) release.complete();
    await holding;
  });

  group('with competing database provisioning', provenance.main);
}
