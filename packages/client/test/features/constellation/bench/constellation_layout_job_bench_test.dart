@Tags(['bench'])
library;

// Pure domain benchmarks use the workspace's transitive test dependency.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../fixtures/resumable_layout_probe.dart';

void main() {
  group('bounded constellation layout units', () {
    test(
      'records startup and every full and incremental unit within '
      '0.5 milliseconds at 1000 nodes',
      () async {
        final measured = await runResumableLayoutProbe('benchmark');
        final report = File('build/bench/constellation_layout_job.json');
        report.parent.createSync(recursive: true);
        report.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(measured),
        );
        final decoded =
            jsonDecode(report.readAsStringSync()) as Map<String, dynamic>;
        expect(decoded, measured);
        expect(decoded['n'], 1000);
        expect(decoded['budgetMicros'], 500);
        expect(decoded['clock'], 'Stopwatch.elapsedTicks');
        expect(decoded['clockFrequency'], greaterThan(0));
        final cases = decoded['cases'] as List<dynamic>;
        final workByMode = <String, List<List<num>>>{};
        expect(cases, hasLength(6));
        expect(
          {
            for (final value in cases)
              '${(value as Map<String, dynamic>)['mode']}/${value['sample']}',
          },
          {
            'full/0',
            'full/1',
            'full/2',
            'incremental/0',
            'incremental/1',
            'incremental/2',
          },
        );
        for (final value in cases) {
          final row = value as Map<String, dynamic>;
          expect(row['n'], 1000);
          expect(row['completedNodes'], 1000);
          expect(row['unitsPerStep'], 1);
          final timings = (row['unitMicros'] as List<dynamic>).cast<num>();
          expect(timings.length, row['unitCount']);
          expect(timings.length, greaterThan(1));
          expect(timings, everyElement(isNonNegative));
          final maximum = timings.reduce((a, b) => a > b ? a : b);
          expect(row['maxUnitMicros'], maximum);
          final startMicros = row['startMicros'] as num;
          expect(startMicros, isNonNegative);
          final allWork = (row['workMicros'] as List<dynamic>).cast<num>();
          expect(allWork, [startMicros, ...timings]);
          expect(row['workCount'], timings.length + 1);
          final maximumWork = allWork.reduce((a, b) => a > b ? a : b);
          expect(row['maxWorkMicros'], maximumWork);
          (workByMode[row['mode'] as String] ??= []).add(allWork);
        }
        // Gate on every observed startup and step duration. Raw samples stay
        // in the report, including scheduling and collector pauses.
        final maxima = <String, num>{};
        for (final entry in workByMode.entries) {
          final samples = entry.value;
          expect(samples, hasLength(3));
          final length = samples.first.length;
          expect(samples.map((work) => work.length), everyElement(length));
          final worst = samples
              .expand((work) => work)
              .reduce((a, b) => a > b ? a : b);
          maxima[entry.key] = worst;
          expect(
            worst,
            lessThanOrEqualTo(500),
            reason:
                '${entry.key} worst startup or step unit across samples: '
                '$worst microseconds',
          );
        }
        report.writeAsStringSync(
          const JsonEncoder.withIndent(
            '  ',
          ).convert({...measured, 'maxWorkMicrosByMode': maxima}),
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}
