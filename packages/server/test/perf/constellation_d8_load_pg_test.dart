// `perf` suites are timing-sensitive, so like `mr` suites they run serialised
// (`-j 1`) and outside the default and plain-`pg` runs.
@Tags(['perf', 'pg', 'mr'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';
import 'constellation_d8_load_harness.dart';
import 'constellation_d8_load_model.dart';

/// D8 load test (#235 U26): publication burst, reconnect burst and concurrent
/// tabs at the owner-declared population (1,000 active sessions), each run at
/// the `load` level and then, on the same database and deployment, at the
/// `capacity` level. Writes `build/perf/d8_<scenario>.json` with
/// `loadEvidence` and `capacityEvidence` (every event record kept).
///
/// A measurement, not a gate: the journal reads the verdict off the report.
/// Each scenario takes about 25 minutes. Environment:
/// * `TENTURA_D8_SCENARIOS`: comma-separated slugs (default: all three);
/// * `TENTURA_D8_WORKERS`: worker isolates (default: processors, as the
///   server's `WORKERS_COUNT` default);
/// * `TENTURA_D8_DEPLOYMENT_FILE`: JSON facts about the deployment under test
///   (images, settings), merged into the report's `deployment`;
/// * `TENTURA_D8_SMOKE_SESSIONS` / `TENTURA_D8_SMOKE_SCALE`: fewer sessions and
///   a compressed timeline, to smoke-test the harness. Such a report is
///   marked `smoke` and is not D8 evidence.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_D8_LOAD_TEST_DB',
    defaultNamePrefix: 'tentura_test_d8_load',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for the D8 load test';
  final environment = Platform.environment;
  final selected = (environment['TENTURA_D8_SCENARIOS'] ?? '').trim();
  final scenarios = selected.isEmpty
      ? D8Scenario.values
      : [for (final slug in selected.split(',')) D8Scenario.fromSlug(slug)];
  final workers =
      int.tryParse(environment['TENTURA_D8_WORKERS'] ?? '') ??
      Platform.numberOfProcessors;
  final sessions =
      int.tryParse(environment['TENTURA_D8_SMOKE_SESSIONS'] ?? '') ??
      d8Sessions;
  final scale =
      double.tryParse(environment['TENTURA_D8_SMOKE_SCALE'] ?? '') ?? 1.0;
  final smoke = sessions != d8Sessions || scale != 1.0;
  final deploymentFile = environment['TENTURA_D8_DEPLOYMENT_FILE'];
  final hostFacts = deploymentFile == null
      ? const <String, Object?>{}
      : jsonDecode(File(deploymentFile).readAsStringSync())
            as Map<String, Object?>;

  for (final scenario in scenarios) {
    test(
      '${scenario.label} at the D8 population writes '
      'build/perf/d8_${scenario.slug}.json',
      () async {
        final session = await setUpDisposablePgWriter(
          target: target,
          createPgmer2Extension: true,
        );
        addTearDown(() => tearDownDisposablePgWriter(session: session));
        final env = target.databaseEnv;
        final dataset = await seedD8Dataset(session.writer);
        final settings = <String, Object?>{};
        for (final name in [
          'server_version',
          'shared_buffers',
          'max_connections',
          'work_mem',
          'shared_preload_libraries',
        ]) {
          settings[name] = (await session.writer.execute(
            'SHOW $name',
          )).first.first;
        }
        settings['pgmer2'] = (await session.writer.execute(
          "SELECT extversion FROM pg_extension WHERE extname = 'pgmer2'",
        )).first.first;

        final harness = await D8Harness.start(
          pg: (
            host: env.pgHost,
            port: env.pgPort,
            database: env.pgDatabase,
            username: env.pgUsername,
            password: env.pgPassword,
          ),
          workers: workers,
          sessions: d8SessionSpecs(scenario, workers, sessions: sessions),
          dataset: dataset,
        );
        final Map<String, Object?> load;
        final Map<String, Object?> capacity;
        final Map<String, Object?> warmUp;
        final List<Map<String, Object?>> workerTotals;
        // Identical for both levels: same process, database and settings.
        final deployment = <String, Object?>{
          ...hostFacts,
          'postgres': settings,
          'server': harness.workerConfig,
          'clientPolicy': {
            'debounceMs': D8ClientPolicy.debounceMs,
            'lazySpacingMs': D8ClientPolicy.lazySpacingMs,
            'jitterMaxMs': 3000,
            'retryLaterHonoured': true,
          },
          'dataset': dataset.toJson(),
          'tabsPerViewer': scenario.tabsPerViewer,
          ...d8ProcessFacts(),
        };
        try {
          warmUp = await harness.warmUp(scale: scale);
          load = await harness.run(
            scenario,
            D8Level.load,
            deployment,
            scale: scale,
          );
          capacity = await harness.run(
            scenario,
            D8Level.capacity,
            deployment,
            scale: scale,
          );
        } finally {
          workerTotals = await harness.close();
        }

        final report = {
          'fixture': 'd8_${scenario.slug}',
          'smoke': smoke,
          'parameters': {
            'scenario': scenario.label,
            'sessions': sessions,
            'workers': workers,
            'tabsPerViewer': scenario.tabsPerViewer,
            'stalenessMs': d8StalenessMs,
            'readsPerWrite': d8ReadsPerWrite,
          },
          'warmUp': warmUp,
          'workerTotals': workerTotals,
          'loadEvidence': load,
          'capacityEvidence': capacity,
        };
        final file = File(
          'build/perf/d8_${scenario.slug}${smoke ? '_smoke' : ''}.json',
        );
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(report));
        stdout
          ..writeln('D8 ${scenario.label} load: ${jsonEncode(load['summary'])}')
          ..writeln(
            'D8 ${scenario.label} capacity: '
            '${jsonEncode(capacity['summary'])}',
          );

        for (final evidence in [load, capacity]) {
          expect(evidence['sessions'], hasLength(sessions));
          expect(evidence['completedRefreshes'], isNotEmpty);
          expect(evidence['publications'], isNotEmpty);
          expect(evidence['deployment'], same(deployment));
        }
      },
      timeout: const Timeout(Duration(minutes: 90)),
      skip: skipReason,
    );
  }
}
