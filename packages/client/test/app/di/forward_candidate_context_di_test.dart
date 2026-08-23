import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated DI composes test, dev, and prod bindings', () {
    final config = File('lib/app/di/di.config.dart').readAsStringSync();

    expect(
      config,
      matches(
        RegExp(
          r'ForwardCandidateContextRepositoryMock\(\)[\s\S]{0,120}'
          r'registerFor: \{_test\}',
        ),
      ),
    );
    expect(
      config,
      matches(
        RegExp(
          r'ForwardCandidateContextRepository\([\s\S]{0,160}'
          r'registerFor: \{_dev, _prod\}',
        ),
      ),
    );
    expect(
      config,
      matches(
        RegExp(
          r'LoadForwardCandidateContextCase\([\s\S]{0,160}'
          r'ForwardCandidateContextRepositoryPort',
        ),
      ),
    );
  });
}
