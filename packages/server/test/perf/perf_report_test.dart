@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'perf_report.dart';

PerfAttempt _attempt({
  int latencyMs = 10,
  int executionMs = 6,
  bool failed = false,
  int queryCount = 3,
  int connectorRpcs = 1,
  int cursorWaitMs = 0,
  int cursorHoldMs = 0,
  int connectionQueueMs = 0,
  int txAgeMs = 0,
  int retryCount = 0,
  int walBytes = 0,
}) => PerfAttempt(
  latency: Duration(milliseconds: latencyMs),
  execution: Duration(milliseconds: executionMs),
  failed: failed,
  queryCount: queryCount,
  connectorRpcs: connectorRpcs,
  cursorWait: Duration(milliseconds: cursorWaitMs),
  cursorHold: Duration(milliseconds: cursorHoldMs),
  connectionQueueTime: Duration(milliseconds: connectionQueueMs),
  txAge: Duration(milliseconds: txAgeMs),
  retryCount: retryCount,
  walBytes: walBytes,
);

Map<String, Object?> _section(Map<String, Object?> json, String key) =>
    json[key]! as Map<String, Object?>;

void main() {
  group('nearestRankPercentile', () {
    test('p50 and p95 of 1..100 are the 50th and 95th ranked values', () {
      final samples = [for (var i = 100; i >= 1; i--) i.toDouble()];

      expect(nearestRankPercentile(samples, 0.50), 50);
      expect(nearestRankPercentile(samples, 0.95), 95);
    });

    test('a single sample is every percentile', () {
      expect(nearestRankPercentile([7], 0.50), 7);
      expect(nearestRankPercentile([7], 0.95), 7);
    });

    test("does not reorder the caller's list", () {
      final samples = [3.0, 1.0, 2.0];

      nearestRankPercentile(samples, 0.50);

      expect(samples, [3.0, 1.0, 2.0]);
    });
  });

  group('PerfReport JSON', () {
    test('reports p50 and p95 of latency in milliseconds', () {
      final report = PerfReport(fixture: 'unit_fixture');
      for (var i = 1; i <= 100; i++) {
        report.add(_attempt(latencyMs: i));
      }

      final latency = _section(report.toJson(), 'latencyMs');

      expect(latency['p50'], closeTo(50, 1e-9));
      expect(latency['p95'], closeTo(95, 1e-9));
    });

    test('failed attempts count towards latency percentiles', () {
      final report = PerfReport(fixture: 'unit_fixture');
      for (var i = 0; i < 18; i++) {
        report.add(_attempt());
      }
      report
        ..add(_attempt(latencyMs: 1000, failed: true))
        ..add(_attempt(latencyMs: 1000, failed: true));

      final json = report.toJson();

      expect(_section(json, 'latencyMs')['p95'], closeTo(1000, 1e-9));
      expect(_section(json, 'latencyMs')['p50'], closeTo(10, 1e-9));
      final attempts = _section(json, 'attempts');
      expect(attempts['total'], 20);
      expect(attempts['failed'], 2);
      expect(attempts['succeeded'], 18);
    });

    test('execution time is reported apart from end-to-end latency', () {
      final report = PerfReport(fixture: 'unit_fixture')
        ..add(_attempt(latencyMs: 40, executionMs: 25));

      final json = report.toJson();

      expect(_section(json, 'latencyMs')['p50'], closeTo(40, 1e-9));
      expect(_section(json, 'executionMs')['p50'], closeTo(25, 1e-9));
    });

    test('counters carry a total and per-attempt percentiles', () {
      final report = PerfReport(fixture: 'unit_fixture')
        ..add(_attempt(queryCount: 4, connectorRpcs: 2, retryCount: 1))
        ..add(_attempt(queryCount: 6, connectorRpcs: 0, walBytes: 8192));

      final json = report.toJson();

      expect(_section(json, 'queryCount')['total'], 10);
      expect(_section(json, 'connectorRpcs')['total'], 2);
      expect(_section(json, 'retryCount')['total'], 1);
      expect(_section(json, 'walBytes')['total'], 8192);
      expect(_section(json, 'queryCount')['p95'], 6);
    });

    test('cursor, connection-queue and transaction-age durations are '
        'summarised in milliseconds', () {
      final report = PerfReport(fixture: 'unit_fixture')
        ..add(
          _attempt(
            cursorWaitMs: 3,
            cursorHoldMs: 20,
            connectionQueueMs: 5,
            txAgeMs: 30,
          ),
        );

      final json = report.toJson();

      expect(_section(json, 'cursorWaitMs')['p50'], closeTo(3, 1e-9));
      expect(_section(json, 'cursorHoldMs')['p95'], closeTo(20, 1e-9));
      expect(_section(json, 'connectionQueueMs')['p50'], closeTo(5, 1e-9));
      expect(_section(json, 'txAgeMs')['p95'], closeTo(30, 1e-9));
    });

    test('WAL attribution is labelled, defaulting to cluster totals', () {
      final defaulted = PerfReport(fixture: 'unit_fixture')..add(_attempt());
      final quiet = PerfReport(
        fixture: 'unit_fixture',
        walAttribution: WalAttribution.quietCluster,
      )..add(_attempt());

      expect(defaulted.toJson()['walAttribution'], 'cluster-total');
      expect(quiet.toJson()['walAttribution'], 'quiet-cluster');
    });

    test('names the fixture, echoes its parameters and carries the EXPLAIN '
        'captures', () {
      final report =
          PerfReport(
              fixture: 'unit_fixture',
              parameters: {'visibleUsers': 100, 'trust': 'sparse'},
            )
            ..add(_attempt())
            ..addExplain(
              const PerfExplainCapture(
                label: 'trust_edges',
                plan: [
                  {
                    'Plan': {'Node Type': 'Seq Scan'},
                  },
                ],
                rolledBack: false,
              ),
            );

      final json = report.toJson();

      expect(json['fixture'], 'unit_fixture');
      expect(json['parameters'], {'visibleUsers': 100, 'trust': 'sparse'});
      final explain = (json['explain']! as List).single as Map;
      expect(explain['label'], 'trust_edges');
      expect(explain['rolledBack'], isFalse);
      expect(explain['plan'], isA<List<Object?>>());
    });

    test('toJson output survives a JSON encode/decode round trip', () {
      final report = PerfReport(fixture: 'unit_fixture')..add(_attempt());

      final decoded = jsonDecode(jsonEncode(report.toJson()));

      expect((decoded as Map)['fixture'], 'unit_fixture');
    });
  });

  group('PerfReport.writeTo', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('perf_report_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes <fixture>.json, creating the output directory', () async {
      final report = PerfReport(fixture: 'unit_fixture')..add(_attempt());
      final nested = Directory('${dir.path}/build/perf');

      final file = await report.writeTo(nested);

      expect(file.path, '${nested.path}/unit_fixture.json');
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      expect(decoded['fixture'], 'unit_fixture');
      expect(decoded['latencyMs'], isA<Map<String, Object?>>());
    });

    test('rejects a fixture name that would escape the output directory', () {
      expect(
        () => PerfReport(fixture: '../escape'),
        throwsArgumentError,
      );
    });

    test('the default output directory is build/perf', () {
      expect(PerfReport.defaultOutputDirectory.path, 'build/perf');
    });

    test('keeps the raw samples and a p95 interval around the p95', () {
      final report = PerfReport(fixture: 'unit_fixture');
      for (var i = 1; i <= 40; i++) {
        report.add(_attempt(latencyMs: i, executionMs: i ~/ 2));
      }

      final json = report.toJson();
      final samples = _section(json, 'samplesMs');
      final latency = _section(json, 'latencyMs');
      final interval = (latency['p95Ci95']! as List<Object?>).cast<double>();

      expect(samples['latency'], [for (var i = 1; i <= 40; i++) i.toDouble()]);
      expect(samples['execution'], hasLength(40));
      expect(interval, hasLength(2));
      expect(interval.first, lessThanOrEqualTo(latency['p95']! as double));
      expect(interval.last, greaterThanOrEqualTo(latency['p95']! as double));
      expect(interval.last, lessThanOrEqualTo(40));
    });
  });

  group('bootstrapP95Interval', () {
    test('is reproducible and collapses on constant samples', () {
      final samples = [for (var i = 0; i < 30; i++) (i * 7 % 13).toDouble()];

      expect(bootstrapP95Interval(samples), bootstrapP95Interval(samples));
      expect(bootstrapP95Interval([5, 5, 5]), [5, 5]);
      expect(bootstrapP95Interval([]), [0, 0]);
    });
  });
}
