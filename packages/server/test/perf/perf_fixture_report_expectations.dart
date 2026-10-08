import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'perf_fixture_matrix.dart';
import 'perf_report.dart';

/// The report [c] must have left in [PerfReport.defaultOutputDirectory]
/// (`build/perf`): non-empty JSON named after the fixture, carrying that
/// fixture's parameters and at least [minAttempts] recorded attempts.
void expectReportWritten(
  PerfFixtureCase c, {
  required File written,
  int minAttempts = 1,
}) {
  final expected = File('build/perf/${c.name}.json');
  expect(written.path, expected.path, reason: c.name);
  expect(expected.existsSync(), isTrue, reason: c.name);

  final text = expected.readAsStringSync();
  expect(text.trim(), isNotEmpty, reason: c.name);

  final json = jsonDecode(text) as Map<String, dynamic>;
  expect(json['fixture'], c.name);
  expect(
    (json['attempts'] as Map<String, dynamic>)['total'] as int,
    greaterThanOrEqualTo(minAttempts),
    reason: c.name,
  );
  final parameters = json['parameters'] as Map<String, dynamic>;
  for (final entry in c.parameters.entries) {
    expect(parameters, containsPair(entry.key, entry.value), reason: c.name);
  }
  expectScenarioEvidence(c, json);
}

/// Writes the report a finished run of [c] leaves behind: its parameters and
/// [attempts] recorded attempts (the first [failedAttempts] of them failed).
Future<File> writeFullReport(
  Directory directory,
  PerfFixtureCase c, {
  int attempts = 3,
  int failedAttempts = 0,
}) {
  final report = PerfReport(fixture: c.name, parameters: c.parameters);
  for (var i = 0; i < attempts; i++) {
    report.add(
      PerfAttempt(
        latency: const Duration(milliseconds: 5),
        execution: const Duration(milliseconds: 4),
        failed: i < failedAttempts,
        queryCount: 1,
        connectorRpcs: 0,
        cursorWait: Duration.zero,
        cursorHold: Duration.zero,
        connectionQueueTime: Duration.zero,
        txAge: Duration.zero,
        retryCount: 0,
        walBytes: 0,
      ),
    );
  }
  return report.writeTo(directory);
}

/// What a scenario case must show in its written report beyond the shared
/// shape: [PerfFixtureMatrix.scenarioEvidenceKeys] are present among its
/// parameters, and a failure-injection run records the failures it injected.
void expectScenarioEvidence(PerfFixtureCase c, Map<String, dynamic> json) {
  final scenario = c.parameters['scenario'];
  if (scenario == null) return;
  final parameters = json['parameters'] as Map<String, dynamic>;
  expect(parameters['scenario'], scenario, reason: c.name);
  expect(
    parameters.keys,
    contains(PerfFixtureMatrix.scenarioEvidenceKeys[scenario]),
    reason: c.name,
  );
  if (scenario == 'failure_injection') {
    expect(
      (json['attempts'] as Map<String, dynamic>)['failed'] as int,
      greaterThan(0),
      reason: '${c.name}: injected failures must show up as failed attempts',
    );
  }
}

/// The JSON object [key] of a perf [report].
Map<String, Object?> reportObject(Map<String, Object?> report, String key) {
  expect(
    report[key],
    isA<Map<String, Object?>>(),
    reason: 'Missing $key metrics',
  );
  return report[key]! as Map<String, Object?>;
}

/// The finite number [key] of a perf [report] object.
num reportNumber(Map<String, Object?> report, String key) {
  expect(report[key], isA<num>(), reason: 'Missing numeric $key metric');
  final value = report[key]! as num;
  expect(value.isFinite, isTrue, reason: '$key must be finite');
  return value;
}
