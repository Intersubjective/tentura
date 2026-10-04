import 'package:test/test.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/use_case/closure_draft_reminder_sweep_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_case.dart';
import 'package:tentura_server/domain/use_case/stale_request_reminder_sweep_case.dart';

import '../support/smoke_env.dart';

/// Boots the [Environment.test] DI graph without Postgres (CI-safe) **once**
/// and checks every non-pg smoke assertion against it. Booting the whole graph
/// costs seconds per file, so closure ports (A11b/A14/A17) and the reminder
/// sweeps (A17) live here instead of in separate one-test files.
void main() {
  test('DI graph resolves under test smoke env', () async {
    addTearDown(() async => getIt.reset());

    await configureDependencies(smokeTestEnv());
    await getIt.allReady(ignorePendingAsyncCreation: true);

    expect(getIt.isRegistered<HelpOfferRepositoryPort>(), isTrue);
    expect(getIt.get<HelpOfferRepositoryPort>(), isNotNull);

    // Closure ports: A17 replaced the A11b no-op receipts binding with the
    // outbox-writing one; A14 replaced the placeholder finalizer.
    expect(getIt.isRegistered<ClosureReceiptsPort>(), isTrue);
    expect(getIt.isRegistered<ClosureFinalizerPort>(), isTrue);
    expect(
      getIt.get<ClosureReceiptsPort>(),
      isNot(isA<NoopClosureReceipts>()),
    );
    expect(getIt.get<ClosureFinalizerPort>(), isA<ClosureFinalizeCase>());

    // A17: both reminder sweeps are registered so the production
    // `TaskWorkerCase.create` factory can supply them.
    expect(getIt.isRegistered<ClosureDraftReminderSweepCase>(), isTrue);
    expect(getIt.isRegistered<StaleRequestReminderSweepCase>(), isTrue);
  });
}
