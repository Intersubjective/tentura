import 'package:test/test.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_case.dart';

import '../support/smoke_env.dart';

/// A11b: non-pg DI smoke — resolves receipt (noop) and the A14 finalizer.
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

    // A14 replaced the A11b placeholder with the real finalizer.
    expect(getIt.get<ClosureFinalizerPort>(), isA<ClosureFinalizeCase>());
  });
}
