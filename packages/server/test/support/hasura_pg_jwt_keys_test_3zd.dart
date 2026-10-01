part of 'hasura_pg_jwt_keys_test.dart';

const _k3zdSleepProbeRelative =
    'test/support/hasura_pg_jwt_3zd_sleep_probe.dart';
const _k3zdWorkspaceDotEnvChildProbeRelative =
    'test/support/hasura_pg_jwt_3zd_workspace_dotenv_child_probe.dart';
const _k3zdWorkspaceInterruptProbePlainName =
    'tentura-3zd workspace harness interrupt probe';

void registerTentura3zdHarnessTests() {
  final workspaceProbeSkip =
      Platform.environment['TENTURA_3ZD_WORKSPACE_PROBE'] != '1'
      ? 'only invoked from architecture workspace probes (tentura-3zd)'
      : false;
  final interruptProbeSkip =
      Platform.environment['TENTURA_3ZD_WORKSPACE_INTERRUPT_PROBE'] != '1'
      ? 'only invoked from architecture workspace SIGKILL probe (tentura-3zd)'
      : false;

  group('tentura-3zd fresh checkout harness safety probes', () {
    test(
      'tentura-3zd workspace fresh-checkout child dotenv probe',
      () async {
        final outcome = await _runFreshCheckoutDartTest([
          _k3zdWorkspaceDotEnvChildProbeRelative,
        ]);
        expect(
          outcome.exitCode,
          0,
          reason:
              'workspace dotenv child probe must succeed '
              '(output:\n${outcome.combined})',
        );
      },
      skip: workspaceProbeSkip,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      _k3zdWorkspaceInterruptProbePlainName,
      () async {
        await _runFreshCheckoutDartTest([_k3zdSleepProbeRelative]);
      },
      skip: interruptProbeSkip,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
