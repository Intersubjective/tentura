// tentura-3zd: subprocess child asserts the workspace repo .env is still present.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'tentura-3zd workspace repo .env exists while fresh-checkout child runs',
    () {
      final serverRoot = Directory.current.path;
      final repoRoot = p.normalize(p.join(serverRoot, '../..'));
      final dotEnv = File(p.join(repoRoot, '.env'));
      expect(
        dotEnv.existsSync(),
        isTrue,
        reason:
            'fresh-checkout harness must not hide or rename the workspace '
            'repo .env before starting the dart test subprocess (tentura-3zd)',
      );
    },
  );
}
