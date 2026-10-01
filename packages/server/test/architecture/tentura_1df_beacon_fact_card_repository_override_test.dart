import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart'
    show runDartAnalyzeSerialized;

/// tentura-1df (tentura-617.13): `BeaconFactCardRepository` must annotate every
/// `BeaconFactCardRepositoryPort` override with `@override` so
/// `dart analyze lib/data/repository/beacon_fact_card_repository.dart` stays
/// free of `annotate_overrides` infos.
///
/// Legacy pre–tentura-617 names from the bead: `latestPublicFactSnippet` →
/// `publicFactSnippetsByBeaconIds`, `correct` → `editText`;
/// `findNonRemovedBySourceMessage` was removed from the port.
const _repositoryRelative =
    'lib/data/repository/beacon_fact_card_repository.dart';
const _portRelative =
    'lib/domain/port/beacon_fact_card_repository_port.dart';

/// Bead-listed sites mapped to the current port / implementation names.
const _beadListedOverrideSites = <String, String>{
  'listForBeacon': 'listForBeacon',
  'pinFact': 'pinFact',
  'setVisibility': 'setVisibility',
  'remove': 'remove',
  'latestPublicFactSnippet': 'publicFactSnippetsByBeaconIds',
  'correct': 'editText',
};

void main() {
  group('tentura-1df BeaconFactCardRepository @override', () {
    test('every BeaconFactCardRepositoryPort method is annotated in the repo',
        () {
      final missing = <String>[];
      for (final method in _portMethodNames()) {
        if (!portMethodHasOverrideAnnotation(
          _repositoryClassSource(),
          method,
        )) {
          missing.add(method);
        }
      }
      expect(
        missing,
        isEmpty,
        reason:
            'add @override before each port implementation in '
            '$_repositoryRelative:\n${missing.join('\n')}',
      );
    });

    test('bead-listed override sites are annotated on the implementation', () {
      final missing = <String>[];
      for (final entry in _beadListedOverrideSites.entries) {
        if (!portMethodHasOverrideAnnotation(
          _repositoryClassSource(),
          entry.value,
        )) {
          missing.add('${entry.key} → ${entry.value}');
        }
      }
      expect(
        missing,
        isEmpty,
        reason:
            'tentura-1df acceptance sites missing @override:\n'
            '${missing.join('\n')}',
      );
    });

    test(
      'override scanner allows blank lines and doc between @override and signature',
      () {
        const samples = <({String name, String method, String source, bool expectAnnotated})>[
          (
            name: 'adjacent',
            method: 'pinFact',
            source: '''
  @override
  Future<void> pinFact() async {}
''',
            expectAnnotated: true,
          ),
          (
            name: 'blank line',
            method: 'setVisibility',
            source: '''
  @override

  Future<void> setVisibility() async {}
''',
            expectAnnotated: true,
          ),
          (
            name: 'doc comment',
            method: 'setVisibility',
            source: '''
  @override
  /// visibility change
  Future<void> setVisibility() async {}
''',
            expectAnnotated: true,
          ),
          (
            name: 'doc before override still counts',
            method: 'pinFact',
            source: '''
  /// pin
  @override
  Future<void> pinFact() async {}
''',
            expectAnnotated: true,
          ),
          (
            name: 'missing override',
            method: 'remove',
            source: '''
  Future<void> remove() async {}
''',
            expectAnnotated: false,
          ),
        ];
        for (final sample in samples) {
          expect(
            portMethodHasOverrideAnnotation(sample.source, sample.method),
            sample.expectAnnotated,
            reason: sample.name,
          );
        }

        final production = _repositoryClassSource();
        expect(
          portMethodHasOverrideAnnotation(production, 'listForBeacon'),
          isTrue,
          reason:
              'production uses doc-then-@override-then-signature for '
              'listForBeacon',
        );
      },
    );

    test(
      'dart analyze reports no annotate_overrides on beacon_fact_card_repository',
      () {
        final result = runDartAnalyzeSerialized(
          ['analyze', '--format=json', _repositoryRelative],
          workingDirectory: _serverPackageRoot().path,
        );
        expect(
          result.exitCode,
          0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}',
        );

        final payload =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        final diagnostics =
            (payload['diagnostics'] as List).cast<Map<String, dynamic>>();
        final annotateOverrides = diagnostics
            .where((d) => d['code'] == 'annotate_overrides')
            .map((d) {
              final location = d['location'] as Map?;
              final line = location == null
                  ? '?'
                  : (location['range'] as Map?)?['start']?['line'];
              final file = location?['file'] ?? _repositoryRelative;
              final message =
                  d['problemMessage']?.toString() ??
                  d['message']?.toString() ??
                  d['code']?.toString();
              return '$file:$line: $message';
            })
            .toList();

        expect(
          annotateOverrides,
          isEmpty,
          reason:
              'annotate_overrides on $_repositoryRelative:\n'
              '${annotateOverrides.join('\n')}',
        );
      },
    );
  });
}

Directory _serverPackageRoot() {
  for (final path in const ['.', '../../packages/server']) {
    final dir = Directory(path);
    final candidate = File('${dir.path}/$_repositoryRelative');
    if (candidate.existsSync()) {
      return dir.absolute;
    }
  }
  throw StateError('server package root not found');
}

File _serverFile(String relativePath) {
  final root = _serverPackageRoot();
  final file = File('${root.path}/$relativePath');
  if (!file.existsSync()) {
    throw StateError('server file not found: ${file.path}');
  }
  return file;
}

List<String> _portMethodNames() {
  final source = _serverFile(_portRelative).readAsStringSync();
  final names = <String>[];
  final declaration = RegExp(
    r'^  Future\b[^\n]*? (\w+)\s*[\({]',
    multiLine: true,
  );
  for (final match in declaration.allMatches(source)) {
    names.add(match.group(1)!);
  }
  expect(names, isNotEmpty, reason: 'parse $_portRelative for port methods');
  return names;
}

String _repositoryClassSource() {
  final source = _serverFile(_repositoryRelative).readAsStringSync();
  final classStart = RegExp(
    r'class BeaconFactCardRepository implements BeaconFactCardRepositoryPort',
  ).firstMatch(source);
  expect(classStart, isNotNull, reason: 'BeaconFactCardRepository class');
  return source.substring(classStart!.start);
}

/// True when [classSource] implements [methodName] with `@override` on the
/// nearest non-doc, non-blank line above the signature, allowing only blank
/// lines and `///` docs in between (stops at `}` or other member bodies).
bool portMethodHasOverrideAnnotation(String classSource, String methodName) {
  final signature = RegExp(
    r'^  \S[^\n]*\b' + RegExp.escape(methodName) + r'\s*\(',
    multiLine: true,
  );
  final lines = classSource.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (!signature.hasMatch(lines[i])) continue;
    var j = i - 1;
    while (j >= 0) {
      final trimmed = lines[j].trim();
      if (trimmed.isEmpty || trimmed.startsWith('///')) {
        j--;
        continue;
      }
      return RegExp(r'^@override\b').hasMatch(trimmed);
    }
    return false;
  }
  return false;
}
