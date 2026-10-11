import 'package:test/test.dart';

import 'package:tentura_server/env.dart';

void main() {
  group('Env pgStatementTimeoutMs', () {
    test('defaults to 30 seconds for request connections', () {
      expect(Env().pgStatementTimeoutMs, 30000);
    });

    test('an explicit value overrides the default', () {
      expect(Env(pgStatementTimeoutMs: 200).pgStatementTimeoutMs, 200);
    });

    test('zero disables the bound', () {
      expect(Env(pgStatementTimeoutMs: 0).pgStatementTimeoutMs, 0);
    });

    test('the pool wait outlasts the statement bound', () {
      for (final ms in [200, 30000]) {
        final env = Env(pgStatementTimeoutMs: ms);
        expect(
          env.pgPoolSettings.connectTimeout,
          greaterThan(Duration(milliseconds: ms)),
          reason: 'a request queued behind a $ms ms statement must not time '
              'out on the pool first',
        );
      }
    });
  });
}
