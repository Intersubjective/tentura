// Host side of integration_test/constellation_profile_web_bench_test.dart:
// writes the browser's numbers to build/bench/ and prints a summary.
// Run through scripts/run_client_profile_web_bench_local.sh.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

const _reportKey = 'constellationProfileWebBench';
const _output = 'build/bench/constellation_profile_web.json';

String _f(Object? value) => value is num ? value.toStringAsFixed(2) : '$value';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final report = data?[_reportKey];
    if (report is! Map<String, dynamic>) {
      throw StateError('The benchmark returned no $_reportKey data');
    }
    final file = File(_output);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        ...report,
        'exportedAtUtc': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    stdout.writeln('[bench] wrote ${file.absolute.path}');
    for (final error in (report['errors'] as List?) ?? const []) {
      stdout.writeln('[bench] ERROR $error');
    }
    stdout.writeln(
      '[bench] N | drag build max/p95 | drag total max/p95 | '
      'pan build max/p95 | pan total max/p95 | drop→settled frame max | '
      'long tasks | longest | drop→ack | drop→settled (ms)',
    );
    for (final entry in report.entries) {
      if (!entry.key.startsWith('n')) continue;
      final n = entry.value as Map<String, dynamic>;
      final drag = n['drag'] as Map<String, dynamic>;
      final pan = n['pan'] as Map<String, dynamic>;
      final drop = n['dropAckReflow'] as Map<String, dynamic>;
      String pair(Map<String, dynamic> m, String key) {
        final stats = m[key] as Map<String, dynamic>;
        return '${_f(stats['max'])}/${_f(stats['p95'])}';
      }

      stdout.writeln(
        '[bench] ${n['size']} | ${pair(drag, 'buildMs')} | '
        '${pair(drag, 'totalSpanMs')} | ${pair(pan, 'buildMs')} | '
        '${pair(pan, 'totalSpanMs')} | '
        '${_f((drop['totalSpanMs'] as Map)['max'])} | '
        '${drop['longTasksOver50Ms']} | ${_f(drop['longestTaskMs'])} | '
        '${_f(drop['dropToAckMs'])} | ${_f(drop['dropToSettledMs'])}',
      );
    }
  },
);
