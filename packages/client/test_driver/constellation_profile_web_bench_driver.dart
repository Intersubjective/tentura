// Host side of integration_test/constellation_profile_web_bench_test.dart:
// writes the browser's numbers to build/bench/ and prints a summary.
// Run through scripts/run_client_profile_web_bench_local.sh.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

const _reportKey = 'constellationProfileWebBench';
const _output = 'build/bench/constellation_profile_web.json';

String _f(Object? value) => value is num ? value.toStringAsFixed(2) : '$value';

String _list(List<Object?> values) =>
    values.isEmpty ? '-' : values.map(_f).join(', ');

List<Object?> _durations(List<Object?> tasks) => [
  for (final t in tasks) (t! as Map)['durationMs'],
];

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
      'grab→first moved frame mouse/touch | drop→ack | drop→settled (ms)',
    );
    final phaseLines = <String>[];
    for (final entry in report.entries) {
      if (!RegExp(r'^n\d+$').hasMatch(entry.key)) continue;
      final n = entry.value as Map<String, dynamic>;
      final drag = n['drag'] as Map<String, dynamic>;
      final pan = n['pan'] as Map<String, dynamic>;
      final drop = n['dropAckReflow'] as Map<String, dynamic>;
      final cycles = (n['cycles'] as Map?)?.cast<String, dynamic>() ?? {};
      String pair(Map<String, dynamic> m, String key) {
        final stats = m[key] as Map<String, dynamic>;
        return '${_f(stats['max'])}/${_f(stats['p95'])}';
      }

      String grab(String kind) {
        final cycle = cycles[kind] as Map<String, dynamic>?;
        if (cycle == null) return '-';
        return _f((cycle['grab'] as Map)['grabToFirstMovedFrameMs']);
      }

      stdout.writeln(
        '[bench] ${n['size']} | ${pair(drag, 'buildMs')} | '
        '${pair(drag, 'totalSpanMs')} | ${pair(pan, 'buildMs')} | '
        '${pair(pan, 'totalSpanMs')} | '
        '${_f((drop['totalSpanMs'] as Map)['max'])} | '
        '${grab('mouse')}/${grab('touch')} | '
        '${_f(drop['dropToAckMs'])} | ${_f(drop['dropToSettledMs'])}',
      );
      final panTasks = _durations((n['pan'] as Map)['longTasks'] as List);
      for (final kind in cycles.keys) {
        final cycle = cycles[kind] as Map<String, dynamic>;
        final byPhase = (cycle['longTasksByPhase'] as Map)
            .cast<String, dynamic>();
        final phases = [
          for (final phase in byPhase.entries)
            [
              phase.key,
              _list((phase.value as Map)['durationsMs'] as List),
            ].join(' '),
        ];
        phaseLines.add(
          '[bench] ${n['size']} $kind: ${phases.join(' | ')}'
          '${kind == 'mouse' ? ' || pan ${_list(panTasks)}' : ''}',
        );
      }
    }
    stdout.writeln('[bench] tasks > 50 ms by phase (ms each):');
    phaseLines.forEach(stdout.writeln);
  },
);
