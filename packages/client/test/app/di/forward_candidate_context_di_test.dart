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
    final repositoryRegistration = RegExp(
      r'gh\.lazySingleton<_i\d+\.ForwardCandidateContextRepositoryPort>',
    ).firstMatch(config);
    final caseRegistration = RegExp(
      r'gh\.singleton<_i\d+\.LoadForwardCandidateContextCase>',
    ).firstMatch(config);
    expect(repositoryRegistration, isNotNull);
    expect(caseRegistration, isNotNull);
    expect(
      repositoryRegistration!.start,
      lessThan(caseRegistration!.start),
      reason: 'the repository port must be registered before the eager case',
    );
  });
}
