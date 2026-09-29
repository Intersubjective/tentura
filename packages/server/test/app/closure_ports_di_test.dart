import 'dart:io';

import 'package:test/test.dart';

/// A11b: generated injectable must bind closure receipt and finalizer ports.
void main() {
  test('generated DI registers closure receipt and finalizer ports', () {
    final config = File('lib/app/di.config.dart').readAsStringSync();

    expect(
      config,
      matches(
        RegExp(
          r'NoopClosureReceipts\(\)[\s\S]{0,160}'
          r'ClosureReceiptsPort',
        ),
      ),
      reason: 'NoopClosureReceipts must register as ClosureReceiptsPort',
    );

    expect(
      config,
      matches(
        RegExp(r'gh\.(?:lazySingleton|singleton)<[^>]*ClosureFinalizerPort>'),
      ),
      reason: 'A11b placeholder must register ClosureFinalizerPort until A14',
    );
  });
}
