// tentura-3d5i: harness sources must not call trust SQL dropped by m0202.
// Post-m0202 cleanup/seed behavior is asserted in
// tentura_3d5i_m0201_clamp_mr_cleanup_pg_test.dart (runtime on disposable pg).

import 'dart:io';

import 'package:test/test.dart';

import '../support/m0202_dropped_trust_sql_usage.dart';

const _harnessPath = 'test/support/m0201_clamp_mr_harness.dart';
const _mrTestPath = 'test/data/database/m0201_clamp_mr_test.dart';

void main() {
  test(
    'm0201 clamp MR harness sources do not use trust objects dropped by m0202',
    () {
      for (final path in [_harnessPath, _mrTestPath]) {
        final source = File(path).readAsStringSync();
        final offenders = droppedTrustSqlUsageInSource(source);
        expect(
          offenders,
          isEmpty,
          reason:
              '$path still uses m0202-dropped trust SQL at lines $offenders',
        );
      }
    },
  );
}
