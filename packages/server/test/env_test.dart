import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';

void main() {
  group('resolveServerEnvironment', () {
    test('enables dev only for an explicit dev value', () {
      expect(resolveServerEnvironment(Environment.dev), Environment.dev);
    });

    test('fails closed to prod for missing or unexpected values', () {
      expect(resolveServerEnvironment(null), Environment.prod);
      expect(resolveServerEnvironment(''), Environment.prod);
      expect(resolveServerEnvironment(Environment.prod), Environment.prod);
      expect(resolveServerEnvironment(Environment.test), Environment.prod);
      expect(resolveServerEnvironment('staging'), Environment.prod);
    });
  });
}
