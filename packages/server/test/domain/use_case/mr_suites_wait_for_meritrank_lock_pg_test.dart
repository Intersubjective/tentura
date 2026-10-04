@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/meritrank_lock_probe.dart';

/// The real `mr`-tagged suites that the use-case directory run executes in
/// parallel with each other. Each must queue behind the MeritRank suite lock
/// *before* it provisions its disposable database; otherwise two of them can
/// overlap on the shared MeritRank container and fail in a different place on
/// every run.
const _suites = <({String file, String databaseEnvVar})>[
  (
    file:
        'test/domain/use_case/'
        'forward_band_witness_admission_integration_pg_test.dart',
    databaseEnvVar: 'TENTURA_G3A_INTEGRATION_TEST_DB',
  ),
  (
    file: 'test/domain/use_case/trust_cutover_case_mr_test.dart',
    databaseEnvVar: 'TENTURA_TRUST_CUTOVER_TEST_DB',
  ),
];

Future<bool> _databaseExists(DisposablePgTarget target, String name) async {
  final admin = await Connection.open(
    target.adminEnv.pgEndpoint,
    settings: target.adminEnv.pgEndpointSettings,
  );
  try {
    final rows = await admin.execute(
      Sql.named('SELECT 1 FROM pg_database WHERE datname = @name'),
      parameters: {'name': name},
    );
    return rows.isNotEmpty;
  } finally {
    await admin.close();
  }
}

Future<void> _dropDatabase(DisposablePgTarget target, String name) async {
  final admin = await Connection.open(
    target.adminEnv.pgEndpoint,
    settings: target.adminEnv.pgEndpointSettings,
  );
  try {
    await admin.execute('DROP DATABASE IF EXISTS "$name" WITH (FORCE)');
  } finally {
    await admin.close();
  }
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MR_SUITE_LOCK_GATE_TEST_DB',
    defaultNamePrefix: 'tentura_test_mr_suite_lock_gate',
  );
  final skipReason = await pgSkipReason(target);

  group('mr-tagged use-case suites', () {
    for (final suite in _suites) {
      test(
        'wait for the MeritRank suite lock before provisioning their database: '
        '${suite.file.split('/').last}',
        () async {
          final childDatabase =
              'tentura_test_lock_gate_${pid}_${suite.databaseEnvVar.length}'
              '_${DateTime.now().microsecondsSinceEpoch}';
          final holder = await holdMeritRankSuiteLock(target);
          Process? child;
          final output = StringBuffer();
          var blockedOnLock = false;
          String? failure;
          try {
            child = await Process.start(
              Platform.resolvedExecutable,
              ['test', suite.file, '-j', '1'],
              environment: {suite.databaseEnvVar: childDatabase},
            );
            final exited = Completer<int>();
            unawaited(child.exitCode.then(exited.complete));
            for (final stream in [child.stdout, child.stderr]) {
              stream
                  .transform(utf8.decoder)
                  .listen(output.write, onError: (Object _) {});
            }

            final deadline = DateTime.now().add(const Duration(minutes: 4));
            while (DateTime.now().isBefore(deadline)) {
              if (exited.isCompleted) {
                failure =
                    'suite exited (${await exited.future}) while the '
                    'MeritRank lock was held elsewhere';
                break;
              }
              if (await _databaseExists(target, childDatabase)) {
                failure =
                    'suite provisioned its database while the '
                    'MeritRank lock was held elsewhere';
                break;
              }
              if (await meritRankSuiteLockWaiterCount(target) > 0) {
                blockedOnLock = true;
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 250));
            }
            failure ??= blockedOnLock
                ? null
                : 'suite never queued on the MeritRank lock';

            // Releasing the lock lets the suite proceed and finish.
            await holder.close();
            await exited.future.timeout(const Duration(minutes: 10));
          } finally {
            child?.kill(ProcessSignal.sigkill);
            await holder.close();
            await _dropDatabase(target, childDatabase);
          }

          expect(
            failure,
            isNull,
            reason:
                'child output tail:\n'
                '${output.toString().split('\n').reversed.take(15).toList().reversed.join('\n')}',
          );
        },
        timeout: const Timeout(Duration(minutes: 20)),
        skip: skipReason,
      );
    }
  });
}
