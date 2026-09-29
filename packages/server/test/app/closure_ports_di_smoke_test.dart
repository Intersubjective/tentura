import 'package:test/test.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/closure/finalize_reason.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';

import '../support/smoke_env.dart';

/// A11b: non-pg DI smoke — resolves receipt (noop) and finalizer (placeholder).
void main() {
  test('closure ports resolve under test smoke env', () async {
    addTearDown(() async => getIt.reset());

    await configureDependencies(smokeTestEnv());
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
