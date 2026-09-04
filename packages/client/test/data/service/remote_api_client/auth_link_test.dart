import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart' show parseString;
import 'package:gql_exec/gql_exec.dart';

import 'package:tentura/data/service/remote_api_client/auth_link.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';

void main() {
  Request pingRequest({Context? context}) => Request(
    operation: Operation(
      document: parseString('query Ping { __typename }'),
      operationName: 'Ping',
    ),
    context: context ?? const Context(),
  );

  const ok = Response(data: {}, response: {});

  test('adds Authorization when getToken returns a bearer', () async {
    final link = AuthLink(() async => 'tok');
    late Request forwarded;
    await link.request(pingRequest(), (r) {
      forwarded = r;
      return Stream.value(ok);
    }).first;

    expect(
      forwarded.context.entry<HttpLinkHeaders>()?.headers['Authorization'],
      'Bearer tok',
    );
  });

  test('throws when an authenticated request has no token', () async {
    final link = AuthLink(() async => null);
    var forwarded = false;
    await expectLater(
      link.request(pingRequest(), (r) {
        forwarded = true;
        return Stream.value(ok);
      }).first,
      throwsA(isA<AuthenticationNoKeyException>()),
    );
    expect(forwarded, isFalse);
  });

  test('throws when an authenticated request has an empty token', () async {
    final link = AuthLink(() async => '');
    var forwarded = false;
    await expectLater(
      link.request(pingRequest(), (r) {
        forwarded = true;
        return Stream.value(ok);
      }).first,
      throwsA(isA<AuthenticationNoKeyException>()),
    );
    expect(forwarded, isFalse);
  });

  test('forwards anonymous requests without calling getToken', () async {
    final link = AuthLink(() async => fail('getToken must not run'));
    var forwarded = false;
    await link.request(
      pingRequest(
        context: const Context().withEntry(const HttpAuthHeaders.noAuth()),
      ),
      (r) {
        forwarded = true;
        expect(r.context.entry<HttpLinkHeaders>(), isNull);
        return Stream.value(ok);
      },
    ).first;
    expect(forwarded, isTrue);
  });
}
