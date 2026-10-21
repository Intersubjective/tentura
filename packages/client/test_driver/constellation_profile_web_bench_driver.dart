// Host side of integration_test/constellation_profile_web_bench_test.dart:
// writes the browser's numbers to build/bench/ and prints a summary.
// Run through scripts/run_client_profile_web_bench_local.sh.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

const _reportKey = 'constellationProfileWebBench';
const _output = 'build/bench/constellation_profile_web.json';

String _f(Object? value) =>
    value == null ? '-' : (value is num ? value.toStringAsFixed(2) : '$value');

/// `p50/p95/max` of a stats map from the benchmark, `-` when it is absent.
String _stats(Object? stats) {
  if (stats is! Map) return '-';
  return [
    for (final k in ['p50', 'p95', 'max']) _f(stats[k]),
  ].join('/');
}

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
    final environment =
        (report['environment'] as Map?)?.cast<String, dynamic>() ?? {};
    final browserMode = switch (environment['headless']) {
      true => 'headless',
      false => 'headed',
      _ => 'headless: -',
    };
    stdout
      ..writeln(
        '[bench] renderer: ${environment['renderer'] ?? '-'} | '
        'crossOriginIsolated: ${environment['crossOriginIsolated'] ?? '-'} | '
        '$browserMode | wasm: ${environment['wasm'] ?? '-'} | '
        'build: ${environment['buildMode'] ?? '-'} | '
        'DPR: ${environment['devicePixelRatio'] ?? '-'} | '
        'WebGL: ${environment['webglRenderer'] ?? '-'}',
      )
      // "fw Frame" is the framework's per-frame "Frame" measure; under skwasm
      // FrameTiming build also counts the wait in the engine's render queue.
      ..writeln(
        '[bench] N | phase | frames | fw Frame p50/p95/max | '
        'build p50/p95/max | raster p50/p95/max | total p50/p95/max (ms)',
      );
    final cycleLines = <String>[];
    final phaseLines = <String>[];
    for (final entry in report.entries) {
      if (!RegExp(r'^n\d+$').hasMatch(entry.key)) continue;
      final n = entry.value as Map<String, dynamic>;
      final drag = n['drag'] as Map<String, dynamic>;
      final pan = n['pan'] as Map<String, dynamic>;
      final drop = n['dropAckReflow'] as Map<String, dynamic>;
      final cycles = (n['cycles'] as Map?)?.cast<String, dynamic>() ?? {};
      for (final (phase, m) in [('drag', drag), ('pan', pan)]) {
        stdout.writeln(
          '[bench] ${n['size']} | $phase | ${m['frames']} | '
          '${_stats(m['frameworkFrameMs'])} | ${_stats(m['buildMs'])} | '
          '${_stats(m['rasterMs'])} | ${_stats(m['totalSpanMs'])}',
        );
      }

      String grab(String kind) {
        final cycle = cycles[kind] as Map<String, dynamic>?;
        if (cycle == null) return '-';
        return _f((cycle['grab'] as Map)['grabToFirstMovedFrameMs']);
      }

      cycleLines.add(
        '[bench] ${n['size']} | '
        '${_f((drop['frameworkFrameMs'] as Map?)?['max'])} | '
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
    stdout.writeln(
      '[bench] N | drop→settled fw Frame max | drop→settled total max | '
      'grab→first moved frame mouse/touch | drop→ack | drop→settled (ms)',
    );
    cycleLines.forEach(stdout.writeln);
    stdout.writeln('[bench] tasks > 50 ms by phase (ms each):');
    phaseLines.forEach(stdout.writeln);
  },
);
