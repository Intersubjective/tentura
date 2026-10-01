// Scoped dart/flutter analyze helpers for client architecture gates.

import 'dart:convert';
import 'dart:io';

typedef ClientAnalyzeHit = ({String relativePath, int lineOneBased, String code});

Directory clientPackageRoot() {
  for (final path in const ['.', '../../packages/client']) {
    final pubspec = File('$path/pubspec.yaml');
    if (pubspec.existsSync()) {
      final nameLine = pubspec.readAsLinesSync().firstWhere(
        (line) => line.startsWith('name:'),
        orElse: () => '',
      );
      if (nameLine.contains('tentura')) {
        return Directory(pubspec.absolute.parent.path);
      }
    }
  }
  throw StateError('client package root not found');
}

bool clientAnalyzePathsEqual(String a, String b) {
  return File(a).absolute.uri.normalizePath().toFilePath() ==
      File(b).absolute.uri.normalizePath().toFilePath();
}

List<Map<String, dynamic>> runDartAnalyzeJsonOnRelativePaths(
  List<String> relativePaths,
) {
  final client = clientPackageRoot();
  const maxAttempts = 3;
  late ProcessResult result;
  var stdout = '';
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    result = Process.runSync(
      'dart',
      ['analyze', '--format=json', ...relativePaths],
      workingDirectory: client.path,
      environment: {
        ...Platform.environment,
        'DART_SUPPRESS_ANALYTICS': 'true',
        'FLUTTER_SUPPRESS_ANALYTICS': 'true',
      },
    );
    stdout = (result.stdout as String).trim();
    if (stdout.isNotEmpty) {
      break;
    }
  }
  if (stdout.isEmpty) {
    throw StateError(
      'dart analyze must emit JSON (exit ${result.exitCode}); '
      'stderr: ${result.stderr}',
    );
  }
  final payload = jsonDecode(stdout) as Map<String, dynamic>;
  return (payload['diagnostics'] as List).cast<Map<String, dynamic>>();
}

int countDartAnalyzeDiagnosticsOnRelativePaths(List<String> relativePaths) {
  return runDartAnalyzeJsonOnRelativePaths(relativePaths).length;
}

int countDartAnalyzeDiagnosticsOnClientPackage() {
  return runDartAnalyzeJsonOnRelativePaths(['.']).length;
}

List<String> dartDiagnosticCodesOnRelativePath(String relativePath) {
  final client = clientPackageRoot();
  final absolute = File('${client.path}/$relativePath').absolute.path;
  return runDartAnalyzeJsonOnRelativePaths([relativePath])
      .where((d) {
        final location = d['location'] as Map?;
        final file = location?['file'] as String?;
        return clientAnalyzePathsEqual(file ?? '', absolute);
      })
      .map((d) => d['code'] as String? ?? '')
      .where((code) => code.isNotEmpty)
      .toList(growable: false);
}

List<ClientAnalyzeHit> dartBeadCodeHitsOnRelativePath({
  required String relativePath,
  required Set<String> beadCodes,
}) {
  final client = clientPackageRoot();
  final absolute = File('${client.path}/$relativePath').absolute.path;
  final hits = <ClientAnalyzeHit>[];
  for (final d in runDartAnalyzeJsonOnRelativePaths([relativePath])) {
    final code = d['code'] as String? ?? '';
    if (!beadCodes.contains(code)) {
      continue;
    }
    final location = d['location'] as Map?;
    final file = location?['file'] as String?;
    if (!clientAnalyzePathsEqual(file ?? '', absolute)) {
      continue;
    }
    final line = (location?['range'] as Map?)?['start']?['line'] as int?;
    hits.add((
      relativePath: relativePath,
      lineOneBased: line ?? -1,
      code: code,
    ));
  }
  return hits;
}

List<ClientAnalyzeHit> beadFlutterLintHitsOnSites({
  required String combinedOutput,
  required String relativePath,
  required List<({int lineOneBased, String code})> beadSites,
}) {
  final parsed = parseFlutterAnalyzeHits(
    combinedOutput: combinedOutput,
    relativePath: relativePath,
  );
  final hits = <ClientAnalyzeHit>[];
  for (final site in beadSites) {
    if (parsed.any(
      (p) => p.lineOneBased == site.lineOneBased && p.code == site.code,
    )) {
      hits.add((
        relativePath: relativePath,
        lineOneBased: site.lineOneBased,
        code: site.code,
      ));
    }
  }
  return hits;
}

List<ClientAnalyzeHit> beadLintHitsOnRelativePaths({
  required List<String> relativePaths,
  required List<({String relativePath, int lineOneBased, String code})>
  beadSites,
}) {
  final client = clientPackageRoot();
  final diagnostics = runDartAnalyzeJsonOnRelativePaths(relativePaths);
  final hits = <ClientAnalyzeHit>[];
  for (final site in beadSites) {
    final absolute = File('${client.path}/${site.relativePath}').absolute.path;
    for (final d in diagnostics) {
      if (d['code'] != site.code) {
        continue;
      }
      final location = d['location'] as Map?;
      final file = location?['file'] as String?;
      if (!clientAnalyzePathsEqual(file ?? '', absolute)) {
        continue;
      }
      final line = (location?['range'] as Map?)?['start']?['line'] as int?;
      if (line == site.lineOneBased) {
        hits.add((
          relativePath: site.relativePath,
          lineOneBased: site.lineOneBased,
          code: site.code,
        ));
      }
    }
  }
  return hits;
}

List<ClientAnalyzeHit> parseFlutterAnalyzeHits({
  required String combinedOutput,
  required String relativePath,
  Set<String>? lintCodes,
}) {
  final hits = <ClientAnalyzeHit>[];
  final normalizedTarget = relativePath.replaceAll('\\', '/');
  final pattern = RegExp(
    r'([^•\n]+\.dart):(\d+):\d+\s+•\s+(\S+)\s*$',
  );
  for (final line in combinedOutput.split('\n')) {
    final match = pattern.firstMatch(line.trim());
    if (match == null) {
      continue;
    }
    final file = match.group(1)!.trim().replaceAll('\\', '/');
    if (!file.endsWith(normalizedTarget)) {
      continue;
    }
    final code = match.group(3)!;
    if (lintCodes != null && !lintCodes.contains(code)) {
      continue;
    }
    hits.add((
      relativePath: relativePath,
      lineOneBased: int.parse(match.group(2)!),
      code: code,
    ));
  }
  return hits;
}

/// Parses `N issues found.` or `No issues found!` from flutter analyze text.
int? parseFlutterAnalyzeIssueCount(String combinedOutput) {
  if (RegExp(r'No issues found!').hasMatch(combinedOutput)) {
    return 0;
  }
  final match = RegExp(r'(\d+) issues found\.').firstMatch(combinedOutput);
  if (match == null) {
    return null;
  }
  return int.parse(match.group(1)!);
}

/// Returns a parsed issue summary after verifying flutter analyze completed.
({int issueCount, String combined}) requireFlutterAnalyzeSummary({
  required CommandOutcome outcome,
  required String relativePath,
}) {
  final combined = '${outcome.stdout}\n${outcome.stderr}';
  final fileName = relativePath.split('/').last;
  if (!combined.contains('Analyzing $fileName')) {
    throw StateError(
      'flutter analyze must run to completion on $relativePath; '
      'exit=${outcome.exitCode} output:\n$combined',
    );
  }
  final issueCount = parseFlutterAnalyzeIssueCount(combined);
  if (issueCount == null) {
    throw StateError(
      'flutter analyze output must include a parseable issue summary '
      '(No issues found! or N issues found.); output:\n$combined',
    );
  }
  return (issueCount: issueCount, combined: combined);
}

CommandOutcome runFlutterAnalyzeOnRelativePaths(List<String> relativePaths) {
  final client = clientPackageRoot();
  final result = Process.runSync(
    'flutter',
    ['analyze', ...relativePaths],
    workingDirectory: client.path,
    environment: {
      ...Platform.environment,
      'DART_SUPPRESS_ANALYTICS': 'true',
      'FLUTTER_SUPPRESS_ANALYTICS': 'true',
    },
  );
  return (
    exitCode: result.exitCode,
    stdout: result.stdout as String,
    stderr: result.stderr as String,
  );
}

typedef CommandOutcome = ({int exitCode, String stdout, String stderr});

String formatClientAnalyzeHits(List<ClientAnalyzeHit> hits) {
  return hits
      .map((h) => '${h.relativePath}:${h.lineOneBased}: ${h.code}')
      .join('\n');
}
