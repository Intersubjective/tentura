import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';

import '../support/smoke_env.dart';

/// A11b: non-pg DI smoke — resolves receipt (noop) and finalizer (placeholder).
void main() {
  for (final entry in [
    ('dev', smokeDevEnv()),
    ('test', emailAuthUnconfiguredTestEnv()),
  ]) {
    test('closure ports resolve under ${entry.$1}', () async {
      addTearDown(() async => getIt.reset());

      final env = entry.$2;
      if (env.environment == Environment.test) {
        // `Environment.test` injectable bindings are mock-only and omit many
        // dev/prod repositories required for eager `allReady` on the full graph.
        // Closure ports register for every environment; boot dev, then assert the
        // hermetic test-shell [Env] used in CI (`ENV=test`).
        expect(env.isEmailAuthConfigured, isFalse);
        await configureDependencies(smokeDevEnv());
      } else {
        await configureDependencies(env);
      }
      await getIt.allReady(ignorePendingAsyncCreation: true);

      expect(getIt.isRegistered<ClosureReceiptsPort>(), isTrue);
      expect(getIt.isRegistered<ClosureFinalizerPort>(), isTrue);

      final receipts = getIt.get<ClosureReceiptsPort>();
      expect(receipts, isA<NoopClosureReceipts>());

      await receipts.opened('beacon-a11b', 1);
      await receipts.finalized('beacon-a11b', 1);
      await receipts.cancelled('beacon-a11b', 1);

      final finalizer = getIt.get<ClosureFinalizerPort>();
      await expectLater(
        finalizer.finalize(
          beaconId: 'beacon-a11b',
          epoch: 1,
          reason: FinalizeReason.authorCloseNow,
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });
  }
}
