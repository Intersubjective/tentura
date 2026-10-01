// tentura-al9: server lib/domain must stay free of data-layer imports and DB types.
//
// Bead acceptance prose is contradictory (it mentions grep still showing hits once
// fixed). These tests encode the intended end state across all of lib/domain:
// no import directive may reach lib/data, drift, or postgres packages, and no
// domain source may reference concrete DB driver or drift query APIs.

import 'dart:io';

import 'package:test/test.dart';

/// Forbidden import targets on a single `import` line (import directives only).
const _forbiddenImportTargetPattern =
    r'(\.\./)+data/|package:tentura_server/data/|package:drift|package:postgres';

final _forbiddenImportLine = RegExp(
  '^import\\s+.*($_forbiddenImportTargetPattern)',
);

/// Same as [_forbiddenImportTargetPattern], scoped to `^import` lines for rg.
const _domainPurityImportRipgrepPattern =
    '^import\\s+.*((\\.\\./)+data/|package:tentura_server/data/|package:drift|package:postgres)';

const _forbiddenDataLayerApiTokens = <String>[
  'TenturaDb',
  'TypedValue',
  'customSelect',
  'customStatement',
];

final _forbiddenDriftVariableBinding = RegExp(r'\bVariable<');

Directory _repoRoot() => Directory('../..').absolute;

String _serverPackageRoot() => '${_repoRoot().path}/packages/server';

Directory _serverDomainLibDir() =>
    Directory('${_serverPackageRoot()}/lib/domain');

String _pathRelativeTo(String filePath, String rootDir) {
  final prefix = rootDir.endsWith('/') ? rootDir : '$rootDir/';
  return filePath.startsWith(prefix)
      ? filePath.substring(prefix.length)
      : filePath;
}

Iterable<File> _domainDartSources() sync* {
  if (!_serverDomainLibDir().existsSync()) {
    return;
  }
  for (final entity in _serverDomainLibDir().listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

void _requireRipgrep() {
  final which = Process.runSync('bash', ['-c', 'command -v rg']);
  expect(
    which.exitCode,
    0,
    reason:
        'ripgrep (rg) is required for domain purity checks (see '
        'scripts/check-server-domain-boundary.sh)',
  );
}

ProcessResult _runDomainPurityImportRipgrep() {
  _requireRipgrep();
  return Process.runSync(
    'rg',
    [_domainPurityImportRipgrepPattern, 'lib/domain'],
    workingDirectory: _serverPackageRoot(),
  );
}

void main() {
  group('tentura-al9 server domain purity grep', () {
    test(
      'import directives under lib/domain do not reach data, drift, or postgres',
      () {
        final result = _runDomainPurityImportRipgrep();
        expect(
          result.exitCode,
          1,
          reason:
              'ripgrep must find no forbidden import lines (exit 1); stdout:\n'
              '${result.stdout}\nstderr:\n${result.stderr}',
        );
        expect(
          result.stdout.toString().trim(),
          isEmpty,
          reason:
              'only import directives are checked; lib/domain must not import '
              'via package:tentura_server/data/, drift/postgres packages, or '
              'relative paths into lib/data/',
        );
      },
    );

    test(
      'every lib/domain dart file keeps import directives off the data layer',
      () {
        final serverRoot = _serverPackageRoot();
        final violations = <String>[];
        for (final file in _domainDartSources()) {
          final rel = _pathRelativeTo(file.path, serverRoot);
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (_forbiddenImportLine.hasMatch(line)) {
              violations.add('$rel:${i + 1}: $line');
            }
          }
        }
        expect(
          violations,
          isEmpty,
          reason:
              'lib/domain import lines must not reference data/drift/postgres:\n'
              '${violations.join('\n')}',
        );
      },
    );

    test(
      'lib/domain sources do not use concrete database or drift query APIs',
      () {
        final serverRoot = _serverPackageRoot();
        final violations = <String>[];
        for (final file in _domainDartSources()) {
          final rel = _pathRelativeTo(file.path, serverRoot);
          final source = file.readAsStringSync();
          for (final token in _forbiddenDataLayerApiTokens) {
            if (source.contains(token)) {
              violations.add('$rel: contains $token');
            }
          }
          if (_forbiddenDriftVariableBinding.hasMatch(source)) {
            violations.add('$rel: drift Variable< binding');
          }
        }
        expect(
          violations,
          isEmpty,
          reason:
              'lib/domain must not reference TenturaDb, postgres TypedValue, '
              'or drift customSelect/customStatement/Variable bindings:\n'
              '${violations.join('\n')}',
        );
      },
    );
  });
}
