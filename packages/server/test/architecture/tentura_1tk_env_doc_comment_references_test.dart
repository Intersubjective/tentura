import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// tentura-1tk (tentura-617.37): `lib/env.dart` doc on [Env.genealogyNodeKeySecret]
/// must not reference names outside analyzer scope (see line ~597).
const _envRelative = 'lib/env.dart';

void main() {
  group('tentura-1tk env.dart comment_references', () {
    test(
      'dart analyze reports no comment_references on lib/env.dart',
      () {
        final result = Process.runSync(
          'dart',
          ['analyze', '--format=json', _envRelative],
          workingDirectory: _serverPackageRoot().path,
        );
        final stdout = result.stdout as String;
        expect(
          stdout.trim(),
          isNotEmpty,
          reason:
              'dart analyze must emit JSON (exit ${result.exitCode}); '
              'stderr: ${result.stderr}',
        );

        final payload = jsonDecode(stdout) as Map<String, dynamic>;
        final diagnostics =
            (payload['diagnostics'] as List).cast<Map<String, dynamic>>();
        final commentReferences = diagnostics
            .where((d) => d['code'] == 'comment_references')
            .map((d) {
              final location = d['location'] as Map?;
              final line = location == null
                  ? '?'
                  : (location['range'] as Map?)?['start']?['line'];
              final column = location == null
                  ? '?'
                  : (location['range'] as Map?)?['start']?['column'];
              final file = location?['file'] ?? _envRelative;
              final message =
                  d['problemMessage']?.toString() ??
                  d['message']?.toString() ??
                  d['code']?.toString();
              return '$file:$line:$column: $message';
            })
            .toList();

        expect(
          commentReferences,
          isEmpty,
          reason:
              'comment_references on $_envRelative:\n'
              '${commentReferences.join('\n')}',
        );
      },
    );
  });
}

Directory _serverPackageRoot() {
  for (final path in const ['.', '../../packages/server']) {
    final dir = Directory(path);
    final candidate = File('${dir.path}/$_envRelative');
    if (candidate.existsSync()) {
      return dir.absolute;
    }
  }
  throw StateError('server package root not found');
}
