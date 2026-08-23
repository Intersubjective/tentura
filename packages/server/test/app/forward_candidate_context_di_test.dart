import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('generated DI composes test, dev, and prod bindings', () {
    final config = File('lib/app/di.config.dart').readAsStringSync();

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
          r'ForwardCandidateContextRepository\([^)]*\)[\s\S]{0,120}'
          r'registerFor: \{_dev, _prod\}',
        ),
      ),
    );
    expect(
      config,
      matches(
        RegExp(
          r'ForwardCandidateContextCase\([\s\S]{0,120}'
          r'ForwardCandidateContextRepositoryPort',
        ),
      ),
    );
  });
}
