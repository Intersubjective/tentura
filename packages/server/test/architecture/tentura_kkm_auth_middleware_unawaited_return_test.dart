import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart'
    show decodeAnalyzeDiagnostics, runDartAnalyzeSerialized, serverPackageRoot;

/// tentura-kkm (tentura-617.3): `AuthMiddleware.verifyBearerJwt` must not
/// trigger analyzer `unawaited_return_in_try_block`. JWT vs inner-handler split
/// and error propagation are covered behaviorally in
/// `test/api/middleware/auth_middleware_test.dart`.
const kKkmAuthMiddlewareRelative = 'lib/api/middleware/auth_middleware.dart';

void main() {
  group('tentura-kkm auth_middleware verifyBearerJwt analyze hygiene', () {
    test(
      'dart analyze reports no unawaited_return_in_try_block on auth_middleware.dart',
      () {
        final result = runDartAnalyzeSerialized(
          ['analyze', '--format=json', kKkmAuthMiddlewareRelative],
          workingDirectory: serverPackageRoot().path,
        );
        final stdout = (result.stdout as String).trim();
        expect(
          stdout,
          isNotEmpty,
          reason:
              'dart analyze must emit JSON (exit ${result.exitCode}); '
              'stderr: ${result.stderr}',
        );

        final unawaited = decodeAnalyzeDiagnostics(stdout)
            .where((d) => d['code'] == 'unawaited_return_in_try_block')
            .map(_formatDiagnostic)
            .toList();

        expect(
          unawaited,
          isEmpty,
          reason:
              'unawaited_return_in_try_block on $kKkmAuthMiddlewareRelative:\n'
              '${unawaited.join('\n')}',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'auth_middleware.dart does not suppress unawaited_return_in_try_block',
      () {
        final path = '${serverPackageRoot().path}/$kKkmAuthMiddlewareRelative';
        final source = File(path).readAsStringSync();
        expect(
          source,
          isNot(contains('ignore: unawaited_return_in_try_block')),
          reason:
              'fix verifyBearerJwt structure instead of suppressing '
              'unawaited_return_in_try_block',
        );
      },
    );
  });
}

String _formatDiagnostic(Map<String, dynamic> d) {
  final location = d['location'] as Map?;
  final line = (location?['range'] as Map?)?['start']?['line'];
  final file = location?['file'] ?? kKkmAuthMiddlewareRelative;
  final message =
      d['problemMessage']?.toString() ??
      d['message']?.toString() ??
      d['code']?.toString() ??
      '?';
  return '$file:$line: $message';
}
