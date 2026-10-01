import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart'
    show runDartAnalyzeSerialized;

/// tentura-21x (tentura-617.3): disposable PG and erasure tests declared
/// upgrade targets, writers, channel fakes, and fixture helpers that were never
/// wired into assertions. Suppressing `unused_*` hid dropped coverage; the fix
/// is to exercise or delete each symbol and keep the listed files green.
const _beadListedTestRelatives = <String>[
  'test/data/database/attention_additive_schema_pg_test.dart',
  'test/data/database/m0141_person_capability_event_ledger_test.dart',
  'test/domain/use_case/user_delete_attention_pg_test.dart',
];

const _relatedUnusedSetupRelatives = <String>[
  'test/data/repository/attention_repository_pg_test.dart',
  'test/domain/use_case/beacon_hierarchy_erasure_pg_test.dart',
];

List<String> get _allGuardedTestRelatives => [
  ..._beadListedTestRelatives,
  ..._relatedUnusedSetupRelatives,
];

/// Nested `run_with_test_cleanup.sh` deletes sibling `/tmp/dart_test.kernel.*`
/// of the unwrapped CI `dart test` process. PG files already run in `test-pg`.
/// `GITHUB_ACTIONS` is not forwarded into the builder container unless the
/// workflow does so; `TEST_TARGET=server` is.
Object get _skipNestedCleanupOnGitHubActions {
  final env = Platform.environment;
  if (env['GITHUB_ACTIONS'] == 'true' ||
      env['CI'] == 'true' ||
      env['TEST_TARGET'] == 'server') {
    return 'do not nest run_with_test_cleanup.sh inside CI dart test';
  }
  return false;
}

void main() {
  group('tentura-21x unused test setup', () {
    group('does not suppress unused_* analyzer warnings', () {
      for (final relative in _allGuardedTestRelatives) {
        test(relative, () {
          expect(
            unusedSetupSuppressions(relative),
            isEmpty,
            reason:
                'remove // ignore: unused_* on $relative instead of hiding '
                'dropped setup:\n'
                '${unusedSetupSuppressions(relative).join('\n')}',
          );
        });
      }
    });

    test(
      'dart analyze . reports no unused_local_variable or unused_element '
      'on guarded test files',
      () {
        expect(
          guardedUnusedSetupDiagnosticsFromPackageAnalyze(),
          isEmpty,
          reason:
              'wire the declared setup or delete it (packages/server '
              'dart analyze .):\n'
              '${guardedUnusedSetupDiagnosticsFromPackageAnalyze().join('\n')}',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    group('unused symbols are wired with real assertions or removed', () {
      test('attention_additive_schema_pg_test.dart', () {
        const relative =
            'test/data/database/attention_additive_schema_pg_test.dart';
        final source = _serverTestSource(relative);
        _expectAbsentOrUsedMoreThanOnce(
          source: source,
          symbol: 'upgradeTarget',
          relative: relative,
          reason:
              'use upgradeTarget in an upgrade-path disposable DB group or '
              'remove the unused target',
        );
        _expectAbsentOrContainsUsage(
          source: source,
          declaration: 'List<Map<String, dynamic>> _notificationUpdates',
          usagePattern: r'_notificationUpdates\(',
          relative: relative,
          reason: 'call _notificationUpdates in a test or delete the helper',
        );
        _expectAbsentOrContainsUsage(
          source: source,
          declaration: 'Future<void> _waitUntil',
          usagePattern: r'await _waitUntil\(',
          relative: relative,
          reason: 'call _waitUntil in a test or delete the helper',
        );
        _expectAbsentOrContainsUsage(
          source: source,
          declaration: 'Future<void> _settle',
          usagePattern: r'await _settle\(\)',
          relative: relative,
          reason: 'call _settle in a test or delete the helper',
        );
      });

      test('m0141_person_capability_event_ledger_test.dart', () {
        const relative =
            'test/data/database/m0141_person_capability_event_ledger_test.dart';
        final source = _serverTestSource(relative);
        if (!source.contains('Future<void> _seedFixture')) {
          return;
        }
        expect(
          source,
          contains('await _seedFixture(writer)'),
          reason:
              'call _seedFixture before write proofs or delete the helper',
        );
        expect(
          source,
          allOf(
            contains('INSERT INTO public.person_capability_event'),
            anyOf(
              contains('pce_forward_reason_uq'),
              contains('source_type = 1'),
              contains('source_type, 1'),
            ),
            anyOf(
              contains('throwsA'),
              contains('expectLater'),
              contains('_expectConstraintViolation'),
            ),
          ),
          reason:
              'm0141 must prove forward_reason / pce_source_type with an '
              'offending or accepted write, not only catalogue queries',
        );
      });

      test('attention_repository_pg_test.dart', () {
        const relative =
            'test/data/repository/attention_repository_pg_test.dart';
        final source = _serverTestSource(relative);
        if (!source.contains('class _TestChannels')) {
          return;
        }
        expect(
          RegExp(r'\b\w+\s*=\s*_TestChannels\(').hasMatch(source),
          isTrue,
          reason: 'instantiate _TestChannels in a test or delete the fake',
        );
        expect(source, contains('AttentionChannelDeliveryCase'));
        expect(
          source,
          allOf(
            anyOf(
              contains('throwOnHandOff: true'),
              contains('throwOnHandOff:true'),
            ),
            anyOf(
              contains('_outboxCount(writer), 0'),
              contains('_deliveryCount(writer), 0'),
              contains('_probeCount(writer), 0'),
            ),
          ),
          reason:
              'channel handoff failure must assert rollback symmetry like '
              'domain/receipt failures',
        );
      });

      test('user_delete_attention_pg_test.dart', () {
        const relative =
            'test/domain/use_case/user_delete_attention_pg_test.dart';
        final source = _serverTestSource(relative);
        if (source.contains('final room = BeaconRoomRepository')) {
          expect(source, matches(RegExp(r'\broom\.')));
        }
        if (source.contains('final helpOffers = HelpOfferRepository')) {
          expect(source, matches(RegExp(r'\bhelpOffers\.')));
        }
        if (source.contains('final commitments = CommitmentRepository')) {
          expect(source, matches(RegExp(r'\bcommitments\.')));
        }
        if (source.contains('class _NoopImageRepository')) {
          expect(
            RegExp(r'[^s]_NoopImageRepository\(').hasMatch(source),
            isTrue,
            reason:
                'use _NoopImageRepository in UserCase wiring or delete the '
                'duplicate noop port',
          );
        }
        if (source.contains('class _NoopTaskRepository')) {
          expect(
            RegExp(r'[^s]_NoopTaskRepository\(').hasMatch(source),
            isTrue,
            reason:
                'use _NoopTaskRepository in UserCase wiring or delete the '
                'duplicate noop port',
          );
        }
      });

      test('beacon_hierarchy_erasure_pg_test.dart', () {
        const relative =
            'test/domain/use_case/beacon_hierarchy_erasure_pg_test.dart';
        final source = _serverTestSource(relative);
        if (!source.contains('AttentionIntentCase')) {
          return;
        }
        if (!source.contains('attentionIntents')) {
          return;
        }
        expect(
          source,
          anyOf(
            contains('attentionIntents.'),
            contains('attentionIntents:'),
            contains('attentionIntents,'),
          ),
          reason:
              'pass attentionIntents into erasure/hierarchy coverage or '
              'delete the unused local',
        );
      });
    });

    group('bead-listed PG test files stay green', () {
      for (final relative in _allGuardedTestRelatives) {
        test(
          relative,
          () {
            final outcome = runGuardedPgTestFile(relative);
            expect(
              outcome.exitCode,
              0,
              reason:
                  '$relative must pass `dart test` after tentura-21x edits\n'
                  'stdout:\n${outcome.stdout}\n'
                  'stderr:\n${outcome.stderr}',
            );
          },
          timeout: const Timeout(Duration(minutes: 12)),
          tags: const ['pg'],
          skip: _skipNestedCleanupOnGitHubActions,
        );
      }
    });
  });
}

void _expectAbsentOrUsedMoreThanOnce({
  required String source,
  required String symbol,
  required String relative,
  required String reason,
}) {
  if (!source.contains(symbol)) {
    return;
  }
  expect(
    RegExp('\\b$symbol\\b').allMatches(source).length,
    greaterThan(1),
    reason: reason,
  );
}

void _expectAbsentOrContainsUsage({
  required String source,
  required String declaration,
  required String usagePattern,
  required String relative,
  required String reason,
}) {
  if (!source.contains(declaration)) {
    return;
  }
  expect(
    RegExp(usagePattern).hasMatch(source),
    isTrue,
    reason: reason,
  );
}

bool _isGuardedTestFile(String? file) {
  if (file == null || file.isEmpty) {
    return false;
  }
  final normalized = file.replaceAll(r'\', '/');
  return _allGuardedTestRelatives.any(
    (relative) => normalized.endsWith('/$relative'),
  );
}

List<String> guardedUnusedSetupDiagnosticsFromPackageAnalyze() {
  final serverRoot = _serverPackageRoot();

  final result = runDartAnalyzeSerialized(
    ['analyze', '--format=json', '.'],
    workingDirectory: serverRoot.path,
    environment: {
      ...Platform.environment,
      'DART_SUPPRESS_ANALYTICS': 'true',
    },
  );
  final stdout = (result.stdout as String).trim();
  expect(
    stdout,
    isNotEmpty,
    reason:
        'dart analyze . must emit JSON (exit ${result.exitCode}); '
        'stderr: ${result.stderr}',
  );

  final payload = jsonDecode(stdout) as Map<String, dynamic>;
  final diagnostics =
      (payload['diagnostics'] as List).cast<Map<String, dynamic>>();
  return diagnostics
      .where(
        (d) =>
            (d['code'] == 'unused_local_variable' ||
                d['code'] == 'unused_element') &&
            _isGuardedTestFile(
              (d['location'] as Map?)?['file'] as String?,
            ),
      )
      .map((d) {
        final location = d['location'] as Map?;
        final line = location == null
            ? '?'
            : (location['range'] as Map?)?['start']?['line'];
        final file = location?['file'] ?? '?';
        final message =
            d['problemMessage']?.toString() ??
            d['message']?.toString() ??
            d['code']?.toString();
        return '$file:$line: $message';
      })
      .toList();
}

List<String> unusedSetupSuppressions(String testRelativePath) {
  final source = _serverTestSource(testRelativePath);
  final hits = <String>[];
  final patterns = <RegExp>[
    RegExp(r'//\s*ignore:\s*unused_(?:element|local_variable)'),
    RegExp(r'ignore_for_file:\s*[^;\n]*unused_(?:element|local_variable)'),
  ];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final pattern in patterns) {
      if (pattern.hasMatch(line)) {
        hits.add('${testRelativePath}:${i + 1}: $line');
      }
    }
  }
  return hits;
}

({int exitCode, String stdout, String stderr}) runGuardedPgTestFile(
  String testRelativePath,
) {
  final wrapper = _testCleanupWrapper();
  // A fresh TMPDIR per nested run keeps the wrapper's own
  // /tmp/dart_test.kernel.* cleanup sweep scoped to this subprocess: without
  // it, the nested wrapper's sweep sees the outer (already-wrapped) `dart
  // test` process's kernel-cache directory as "unreferenced" (its name is
  // never a literal argv token) and deletes it out from under the outer
  // process, crashing the outer run with a PathNotFoundException after all
  // guarded tests have already passed.
  final nestedTmp = Directory.systemTemp.createTempSync(
    'tentura-21x-nested-',
  );
  try {
    final result = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '11m',
        '--',
        'dart',
        'test',
        testRelativePath,
      ],
      workingDirectory: _serverPackageRoot().path,
      environment: {
        ...Platform.environment,
        'DART_SUPPRESS_ANALYTICS': 'true',
        'TMPDIR': nestedTmp.path,
      },
    );
    return (
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  } finally {
    nestedTmp.deleteSync(recursive: true);
  }
}

String _serverTestSource(String relativePath) {
  final file = File('${_serverPackageRoot().path}/$relativePath');
  if (!file.existsSync()) {
    throw StateError('server test file not found: ${file.path}');
  }
  return file.readAsStringSync();
}

File _testCleanupWrapper() {
  final serverRoot = _serverPackageRoot();
  final candidates = [
    File('${serverRoot.path}/../../scripts/run_with_test_cleanup.sh'),
    File('${serverRoot.parent.parent.path}/scripts/run_with_test_cleanup.sh'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return file.absolute;
    }
  }
  throw StateError('scripts/run_with_test_cleanup.sh not found');
}

Directory _serverPackageRoot() {
  for (final path in const ['.', '../../packages/server']) {
    final dir = Directory(path);
    final candidate = File('${dir.path}/lib/env.dart');
    if (candidate.existsSync()) {
      return dir.absolute;
    }
  }
  throw StateError('server package root not found');
}
