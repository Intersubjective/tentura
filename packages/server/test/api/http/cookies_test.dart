import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/http/cookies.dart';
import 'package:tentura_server/consts.dart';

void main() {
  test('parseCookies reads multiple cookies', () {
    final request = Request(
      'GET',
      Uri.parse('http://localhost/'),
      headers: {'cookie': 'a=1; b=two; c='},
    );
    expect(parseCookies(request), {'a': '1', 'b': 'two', 'c': ''});
  });

  test('buildSetCookie enforces __Host- rules', () {
    final value = buildSetCookie(
      name: kCookieSessionName,
      value: 'tok',
      maxAgeSeconds: 60,
    );
    expect(value, contains('HttpOnly'));
    expect(value, contains('Secure'));
    expect(value, contains('SameSite=Lax'));
    expect(value, contains('Path=/'));
    expect(value, startsWith('$kCookieSessionName=tok'));
  });

  test('withSetCookie appends multiple Set-Cookie headers', () {
    final headers = withSetCookie(
      withSetCookie({}, buildClearCookie(kCookieOAuthStateName)),
      buildSetCookie(name: kCookieSessionName, value: 'x', maxAgeSeconds: 1),
    );
    final cookies = headers['set-cookie']! as List<String>;
    expect(cookies, hasLength(2));
  });
}
