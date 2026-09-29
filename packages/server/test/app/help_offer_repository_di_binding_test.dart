import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('generated DI composes test mock and dev/prod repository bindings', () {
    final config = File('lib/app/di.config.dart').readAsStringSync();

    expect(
      config,
      matches(
        RegExp(
          r'HelpOfferRepositoryMock\(\)[\s\S]{0,120}'
          r'registerFor: \{_test\}',
        ),
      ),
    );
    expect(
      config,
      matches(
        RegExp(
          r'HelpOfferRepository\([^)]*\)[\s\S]{0,120}'
          r'registerFor: \{_dev, _prod\}',
        ),
      ),
    );
  });
}
