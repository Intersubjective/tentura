import 'package:test/test.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';

import '../support/smoke_env.dart';

/// Boots [Environment.test] DI graph without Postgres (CI-safe).
void main() {
  test('DI graph resolves under test smoke env', () async {
    addTearDown(() async => getIt.reset());

    await configureDependencies(smokeTestEnv());
    await getIt.allReady(ignorePendingAsyncCreation: true);

    expect(getIt.isRegistered<HelpOfferRepositoryPort>(), isTrue);
    expect(getIt.get<HelpOfferRepositoryPort>(), isNotNull);

    expect(getIt.isRegistered<ClosureReceiptsPort>(), isTrue);
    expect(getIt.isRegistered<ClosureFinalizerPort>(), isTrue);
  });
}
