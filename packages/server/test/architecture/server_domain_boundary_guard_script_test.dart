import 'dart:io';

import 'package:test/test.dart';

/// alloy:lesson:domain_boundary_rg_guard_inverted — CI uses inverted rg; agents
/// should run the same guard via a repo script (exit 0 when domain is clean).
void main() {
  test('scripts/check-server-domain-boundary.sh exists and passes on a clean tree', () {
    final repoRoot = Directory('../..').absolute;
    final script = File('${repoRoot.path}/scripts/check-server-domain-boundary.sh');
    expect(
      script.existsSync(),
      isTrue,
      reason: 'add ${script.path} wrapping ! rg domain→data/repository guard',
    );
    expect(
      script.statSync().modeString(),
      contains('x'),
      reason: 'boundary guard must be executable',
    );

    final result = Process.runSync(
      'bash',
      [script.path],
      workingDirectory: repoRoot.path,
    );
    expect(
      result.exitCode,
      0,
      reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
  });
}
