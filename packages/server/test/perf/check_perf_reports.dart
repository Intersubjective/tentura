import 'dart:io';

import 'perf_fixture_matrix.dart';

/// `dart run test/perf/check_perf_reports.dart <dir>`: exits non-zero and
/// names every matrix fixture without a full JSON report in `<dir>`.
void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: check_perf_reports.dart <report directory>');
    exit(2);
  }
  final missing = PerfFixtureMatrix.missingReports(Directory(args.single));
  if (missing.isEmpty) {
    stdout.writeln(
      'all ${PerfFixtureMatrix.cases.length} perf reports are present',
    );
    return;
  }
  stderr.writeln('missing or incomplete perf reports in ${args.single}:');
  for (final name in missing) {
    stderr.writeln('  $name');
  }
  exit(1);
}
