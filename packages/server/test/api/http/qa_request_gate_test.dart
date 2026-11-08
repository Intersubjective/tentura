import 'package:injectable/injectable.dart' show Environment;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/http/qa_request_gate.dart';
import 'package:tentura_server/env.dart';

void main() {
  Env env({
    String environment = Environment.test,
    bool qaAuthEnabled = true,
    String qaAuthToken = 'secret',
  }) => Env(
    environment: environment,
    serverUri: Uri.parse('https://test.tentura.local'),
    qaAuthEnabled: qaAuthEnabled,
    qaAuthToken: qaAuthToken,
  );

  Request request({String? queryToken, String? authorization}) => Request(
    'POST',
    Uri.parse('http://localhost/_qa/x').replace(
      queryParameters: queryToken == null ? null : {'_qa_token': queryToken},
    ),
    headers: {'authorization': ?authorization},
  );

  test('the _qa_token query parameter is accepted', () {
    expect(isQaRequestAllowed(request(queryToken: 'secret'), env()), isTrue);
  });

  for (final header in ['Bearer secret', 'bearer secret', 'BEARER  secret ']) {
    test('an Authorization header "$header" is accepted', () {
      expect(
        isQaRequestAllowed(request(authorization: header), env()),
        isTrue,
      );
    });
  }

  test('either token matching is enough', () {
    expect(
      isQaRequestAllowed(
        request(queryToken: 'wrong', authorization: 'Bearer secret'),
        env(),
      ),
      isTrue,
    );
    expect(
      isQaRequestAllowed(
        request(queryToken: 'secret', authorization: 'Bearer wrong'),
        env(),
      ),
      isTrue,
    );
  });

  for (final token in ['', 'secre', 'secreT', 'secret2', 'xsecret']) {
    test('a wrong token "$token" is refused', () {
      expect(isQaRequestAllowed(request(queryToken: token), env()), isFalse);
      expect(
        isQaRequestAllowed(request(authorization: 'Bearer $token'), env()),
        isFalse,
      );
    });
  }

  test('no token is refused', () {
    expect(isQaRequestAllowed(request(), env()), isFalse);
  });

  test('a non-bearer Authorization header is refused', () {
    expect(
      isQaRequestAllowed(request(authorization: 'Basic secret'), env()),
      isFalse,
    );
  });

  test('refused when QA auth is disabled, even with the right token', () {
    expect(
      isQaRequestAllowed(
        request(queryToken: 'secret'),
        env(qaAuthEnabled: false),
      ),
      isFalse,
    );
  });

  test('refused when the configured token is empty', () {
    expect(
      isQaRequestAllowed(request(queryToken: ''), env(qaAuthToken: '')),
      isFalse,
    );
  });
}
