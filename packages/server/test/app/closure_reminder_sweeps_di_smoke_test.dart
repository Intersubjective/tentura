import 'package:test/test.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/use_case/closure_draft_reminder_sweep_case.dart';
import 'package:tentura_server/domain/use_case/stale_request_reminder_sweep_case.dart';

import '../support/smoke_env.dart';

/// A17: non-pg DI smoke — both reminder sweeps are registered (so the
/// production `TaskWorkerCase.create` factory can supply them) and the
/// receipts port is no longer the A11b placeholder.
void main() {
  test('reminder sweeps resolve and receipts are real', () async {
    addTearDown(() async => getIt.reset());

    await configureDependencies(smokeTestEnv());
    await getIt.allReady(ignorePendingAsyncCreation: true);

    expect(getIt.isRegistered<ClosureDraftReminderSweepCase>(), isTrue);
    expect(getIt.isRegistered<StaleRequestReminderSweepCase>(), isTrue);
    expect(getIt.get<ClosureReceiptsPort>(), isNot(isA<NoopClosureReceipts>()));
  });
}
