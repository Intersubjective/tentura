// #1173 split: the error link's GraphQL-error handler maps a null or empty
// error list the way every other failure path is mapped (mapRemoteFailure:
// UnknownException / RemoteApiException) instead of throwing a bare
// `Exception('null')` / `Exception('[]')`. (gql_error_link itself only calls
// the handler with a non-empty list; this pins the handler's own fallback.)

import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show GraphQLError;

import 'package:tentura/data/service/remote_api_client/build_client.dart';
import 'package:tentura/domain/exception/generic_exception.dart';

void main() {
  test('a null error list throws UnknownException', () {
    expect(
      () => throwGraphQLErrors(null),
      throwsA(isA<UnknownException>()),
    );
  });

  test("an empty error list throws RemoteApiException('[]')", () {
    expect(
      () => throwGraphQLErrors(const []),
      throwsA(
        isA<RemoteApiException>().having((e) => e.message, 'message', '[]'),
      ),
    );
  });

  test('an error without extensions keeps the server message', () {
    expect(
      () => throwGraphQLErrors(const [GraphQLError(message: 'nope')]),
      throwsA(
        isA<RemoteApiException>().having((e) => e.message, 'message', 'nope'),
      ),
    );
  });
}
