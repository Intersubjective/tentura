// Like the other server architecture AST checks, analyzer is transitive.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';

// Repository cleanup assertions only: never execute the obsolete gates or git.
const _obsoleteTestPaths = <String>[
  'test/architecture/tentura_1ev_landing_check_test.dart',
  'test/architecture/tentura_28f_landing_check_test.dart',
  'test/architecture/tentura_2no_landing_check_test.dart',
  'test/architecture/tentura_30e_landing_check_nesting_test.dart',
  'test/architecture/tentura_3i0m_landing_check_test.dart',
  'test/architecture/tentura_3w2_landing_check_test.dart',
  'test/architecture/tentura_8u7_landing_check_test.dart',
  'test/architecture/tentura_fx7_landing_check_test.dart',
  'test/architecture/tentura_j0q_landing_check_test.dart',
  'test/architecture/tentura_olc_landing_check_test.dart',
  'test/architecture/tentura_pl4_landing_check_test.dart',
  'test/architecture/tentura_u6e_landing_check_test.dart',
  'test/architecture/tentura_amn_8u7_worktree_remediation_test.dart',
  'test/architecture/tentura_pl4_di_acceptance_probe_test.dart',
  'test/architecture/tentura_0cl_agents_olc_fixture_test.dart',
];

// These files serve independent analyzer purposes. This cleanup check inspects
// only obsolete-gate dependencies, leaving equivalent assertions unrestricted.
const _reviewedChecks = <String>[
  'test/architecture/tentura_1tk_env_doc_comment_references_test.dart',
  'test/architecture/tentura_1df_beacon_fact_card_repository_override_test.dart',
  'test/architecture/tentura_5zq_server_ci_analyze_gate_test.dart',
  'test/architecture/tentura_21x_unused_test_setup_test.dart',
  'test/architecture/server_package_analysis_test.dart',
];

// Individually reviewed obsolete helpers: the olc functions locate/run a
// deleted test; the 8u7 helpers check ancestry or build/run its frozen checkout.
// The CI-only runOlcAcceptanceServerLintGate alias, reusable suite/codegen
// helpers and callback typedefs are allowed despite their historical names.
const _obsoleteHarnessSymbols = <String>{
  'olcLandingCheckTestFile',
  'runOlcBeadAcceptanceDartTest',
  '_8u7TrialMergeRef',
  'bead8u7TransientStateSkip',
  'run3i0mAcceptanceFourFileDartTestOn8u7TrialMerge',
  'run3w2Bare8u7RequiredCheckLeafDartTest',
  '_mergeLandingTargetInto8u7TrialMerge',
  '_runIn8u7TrialMergeWorktree',
};

void main() {
  group('tentura-qp1i obsolete Alloy landing gates removed', () {
    test('all 15 confirmed-dead test files are absent', () {
      final server = _serverPackageRoot();
      final remaining = _obsoleteTestPaths.where(
        (path) =>
            FileSystemEntity.typeSync('${server.path}/$path') !=
            FileSystemEntityType.notFound,
      );

      expect(
        remaining,
        isEmpty,
        reason:
            'Alloy no longer creates bead worktrees or trial merges; '
            'delete these obsolete acceptance tests.',
      );
    });

    test('AGENTS.md no longer carries obsolete landing acceptance markers', () {
      final agents = File('${_serverPackageRoot().path}/../../AGENTS.md');
      final markers = RegExp(
        r'<!--\s*tentura-\S+\s+landing gate acceptance\b[\s\S]*?-->',
      ).allMatches(agents.readAsStringSync()).map((match) => match.group(0)!);

      expect(
        markers,
        isEmpty,
        reason:
            'Remove the self-referential comments from the old Alloy '
            'landing process.',
      );
    });

    test('reviewed analyzer tests have no obsolete gate dependencies', () {
      expect(
        _obsoleteSymbolReferences(
          'indirect.dart',
          _parse('''
void main() {
  test('legacy runner', () {
    olcLandingCheckTestFile();
    runOlcBeadAcceptanceDartTest();
  });
}
'''),
        ),
        containsAll([
          'indirect.dart: olcLandingCheckTestFile',
          'indirect.dart: runOlcBeadAcceptanceDartTest',
        ]),
      );
      final server = _serverPackageRoot();
      final obsoleteReferences = <String>[];
      for (final relative in _reviewedChecks) {
        final file = File('${server.path}/$relative');
        expect(file.existsSync(), isTrue, reason: relative);
        final source = file.readAsStringSync();
        final unit = _parse(source);
        obsoleteReferences.addAll(_obsoleteReferences(relative, source));
        obsoleteReferences.addAll(_obsoleteSymbolReferences(relative, unit));
        if (source.contains('landing gate acceptance')) {
          obsoleteReferences.add('$relative: landing gate acceptance');
        }
      }

      expect(
        obsoleteReferences,
        isEmpty,
        reason:
            'Keep the independent analyzer checks, removing only their '
            'dependencies on deleted landing tests and marker assertions.',
      );
    });

    test('shared lint harness drops obsolete worktree and landing helpers', () {
      expect(
        _obsoleteSymbolReferences(
          'generic.dart',
          _parse('''
void createIndependentWorktree() {
  Process.runSync('git', ['worktree', 'add', '--detach', 'alloy/tentura-other']);
}
// This historical alias implements an independent CI check, not a landing.
CommandOutcome runOlcAcceptanceServerLintGate() => runServerCiLintGateFromRepoRoot();
void _generateIgnoredSourcesIn8u7TrialMerge(Directory serverPackage) {
  Process.runSync('dart', ['run', 'build_runner', 'build', '-d'],
      workingDirectory: serverPackage.path);
}
void independentCheck() {
  const successfulExit = 0;
  final result = runOlcAcceptanceServerLintGate();
  final exit = result.exitCode;
  expect(exit, equals(successfulExit));
}
'''),
        ),
        isEmpty,
        reason:
            'Independent worktree/codegen/CI helpers and equivalent '
            'assertion spellings are allowed.',
      );
      final fixture = Directory.systemTemp.createTempSync(
        'tentura-qp1i-imports-',
      );
      try {
        Directory('${fixture.path}/test/support').createSync(recursive: true);
        File('${fixture.path}/test/support/independent.dart').writeAsStringSync(
          "import 'server_ci_lint_gate_harness.dart';\n",
        );
        expect(
          _remainingHarnessConsumers(fixture),
          ['test/support/independent.dart: server_ci_lint_gate_harness.dart'],
          reason: 'A deleted harness with a surviving import must be rejected.',
        );
      } finally {
        fixture.deleteSync(recursive: true);
      }
      const relative = 'test/support/server_ci_lint_gate_harness.dart';
      final server = _serverPackageRoot();
      final harness = File('${server.path}/$relative');
      if (!harness.existsSync()) {
        expect(
          _remainingHarnessConsumers(server),
          isEmpty,
          reason:
              'Delete the harness only after migrating its remaining '
              'import/export/part consumers, including the 6koo support code.',
        );
        return;
      }
      final source = harness.readAsStringSync();
      final obsoleteReferences = _obsoleteReferences(relative, source);
      obsoleteReferences.addAll(
        _obsoleteSymbolReferences(relative, _parse(source)),
      );

      expect(
        obsoleteReferences,
        isEmpty,
        reason:
            'Generic lint helpers may remain for independent consumers; '
            'the individually identified obsolete landing/trial-merge helpers '
            'and their references to deleted tests must go.',
      );
    });
  });
}

List<String> _obsoleteReferences(String relative, String source) => [
  for (final path in _obsoleteTestPaths)
    if (source.contains(path.split('/').last)) '$relative: $path',
];

CompilationUnit _parse(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  expect(result.errors, isEmpty, reason: 'architecture source must parse');
  return result.unit;
}

List<String> _obsoleteSymbolReferences(String relative, CompilationUnit unit) {
  final hits = <String>{};
  // The parser token stream excludes comments and distinguishes identifier
  // tokens from quoted strings, so indirect calls/references cannot hide behind
  // the absence of a deleted filename literal.
  var token = unit.beginToken;
  while (token != unit.endToken) {
    if (_obsoleteHarnessSymbols.contains(token.lexeme)) {
      hits.add('$relative: ${token.lexeme}');
    }
    token = token.next!;
  }
  return hits.toList();
}

List<String> _remainingHarnessConsumers(Directory server) {
  final consumers = <String>[];
  for (final root in const ['lib', 'test', 'tool', 'bin']) {
    final directory = Directory('${server.path}/$root');
    if (!directory.existsSync()) continue;
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final relative = file.path.substring(server.path.length + 1);
      // These files are required to disappear, so only surviving consumers
      // constrain whether the shared harness can be deleted.
      if (_obsoleteTestPaths.contains(relative)) continue;
      final source = file.readAsStringSync();
      if (!source.contains('server_ci_lint_gate_harness.dart')) continue;
      final unit = _parse(source);
      for (final directive in unit.directives.whereType<UriBasedDirective>()) {
        final uri = directive.uri.stringValue;
        if (uri != null &&
            uri.split('/').last == 'server_ci_lint_gate_harness.dart') {
          consumers.add('$relative: $uri');
        }
      }
    }
  }
  return consumers;
}

Directory _serverPackageRoot() {
  for (final path in const ['.', 'packages/server', '../../packages/server']) {
    final directory = Directory(path);
    if (File('${directory.path}/lib/env.dart').existsSync()) {
      return directory.absolute;
    }
  }
  throw StateError('server package root not found');
}
