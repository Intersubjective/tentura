import 'package:test/test.dart';

import 'package:tentura_server/domain/unsubscribe/unsubscribe_token.dart';

void main() {
  const token = UnsubscribeToken('test-secret');

  test('round-trips a signed token', () {
    final t = token.sign(accountId: 'acc-1', scope: 'asksOfMe');
    final payload = token.verify(t);
    expect(payload, isNotNull);
    expect(payload!.accountId, 'acc-1');
    expect(payload.scope, 'asksOfMe');
  });

  test('rejects a tampered signature', () {
    final t = token.sign(accountId: 'acc-1', scope: 'all');
    final tampered = '${t.substring(0, t.length - 2)}xy';
    expect(token.verify(tampered), isNull);
  });

  test('rejects a token signed with a different secret', () {
    final other = const UnsubscribeToken('other-secret')
        .sign(accountId: 'acc-1', scope: 'all');
    expect(token.verify(other), isNull);
  });

  test('rejects malformed input', () {
    expect(token.verify(''), isNull);
    expect(token.verify('no-dot'), isNull);
    expect(token.verify('.'), isNull);
  });
}
