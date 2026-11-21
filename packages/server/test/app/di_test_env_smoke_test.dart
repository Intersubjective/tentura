import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/service/pg_notification_connection.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/use_case/closure_draft_reminder_sweep_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_case.dart';
import 'package:tentura_server/domain/use_case/stale_request_reminder_sweep_case.dart';

import '../support/smoke_env.dart';
import '../support/test_di.dart';
import '../support/test_dependency_graph_expectations.dart';

/// Boots the test DI graph without Postgres. The smoke test checks the closure
/// ports (A11b/A14/A17) and reminder sweeps (A17) against a single graph boot.
///
/// The graph's only eager Postgres connection is [PgNotificationService]'s
/// LISTEN connection, opened by a non-lazy async singleton while the graph is
/// built. Its refused connect fails inside get_it's own future chain, so the
/// test cannot catch it, and it fails the test whenever Postgres is down (the
/// non-pg CI job). The test therefore pre-registers an offline connector; the
/// real service and everything that awaits it still resolve through the graph.
void main() {
  test('DI graph resolves under test smoke env', () async {
    _useOfflinePgNotifications();
    await configureTestDependencies(smokeTestEnv());
    await getIt.allReady(ignorePendingAsyncCreation: true);
    expect(
      await getIt.getAsync<PgNotificationService>(),
      isA<PgNotificationService>(),
    );

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

  test('the test graph resolves its dependencies without PostgreSQL', () async {
    _useOfflinePgNotifications();
    await expectTestDependencyGraph(smokeTestEnv());
  });
}

void _useOfflinePgNotifications() {
  addTearDown(() async {
    await getIt.reset();
    getIt.skipDoubleRegistration = false;
  });

  getIt
    ..skipDoubleRegistration = true
    ..registerSingleton<PgNotificationConnector>(
      const _OfflinePgNotificationConnector(),
    );
}

/// Opens LISTEN connections that never deliver anything and need no server.
final class _OfflinePgNotificationConnector implements PgNotificationConnector {
  const _OfflinePgNotificationConnector();

  @override
  Future<PgNotificationConnection> open(
    Endpoint endpoint, {
    required ConnectionSettings settings,
  }) async => _OfflinePgNotificationConnection();
}

final class _OfflinePgNotificationConnection
    implements PgNotificationConnection {
  final _channel = StreamController<String>.broadcast();

  @override
  Stream<String> channel(String name) => _channel.stream;

  @override
  Future<void> listen(String channel) async {}

  @override
  Future<void> notify(String channel, String payload) async {}

  @override
  Future<void> close() => _channel.close();
}
