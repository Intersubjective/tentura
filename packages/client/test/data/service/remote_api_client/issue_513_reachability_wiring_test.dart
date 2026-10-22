import 'package:ferry/ferry.dart'
    show Client, DataSource, FetchPolicy, JsonOperationRequest;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart' show parseString;
import 'package:gql_exec/gql_exec.dart' show Operation;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;

import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/data/service/remote_api_client/build_client.dart';

/// What the fake server does with the next request.
enum _Answer { networkDown, data, graphQlError }

/// #513: the HTTP client is where an offline browser is first noticed. It
/// must tell [NetworkReachability] about a transport failure, and about any
/// answer from the server (data or a GraphQL error) as reachable again.
void main() {
  var answer = _Answer.data;

  Future<Client> buildFakeClient(NetworkReachability reachability) =>
      buildClient(
        params: (
          apiEndpointUrl: 'https://example.test/api/v1/graphql',
          apiEndpointUrlV2: 'https://example.test/api/v2/graphql',
          userAgent: 'test',
          requestTimeout: const Duration(seconds: 2),
        ),
        getToken: () async => 'test-token',
        httpClient: MockClient(
          (_) async => switch (answer) {
            _Answer.networkDown => throw http.ClientException(
              'Failed to fetch',
            ),
            _Answer.data => http.Response(
              '{"data":{"__typename":"Query"}}',
              200,
              headers: {'content-type': 'application/json'},
            ),
            _Answer.graphQlError => http.Response(
              '{"errors":[{"message":"Discussion is closed", '
              '"extensions":{"code":"1501"}}]}',
              200,
              headers: {'content-type': 'application/json'},
            ),
          },
        ),
        reachability: reachability,
      );

  Future<void> ping(Client client) async {
    final request = JsonOperationRequest(
      operation: Operation(
        document: parseString('query Ping { __typename }'),
        operationName: 'Ping',
      ),
      fetchPolicy: FetchPolicy.NoCache,
      vars: const {},
    );
    try {
      await client
          .request(request)
          .where((event) => event.dataSource == DataSource.Link)
          .first
          .timeout(const Duration(seconds: 3));
    } on Object catch (_) {
      // Failures are the point of some pings; the reachability is asserted.
    }
  }

  group('issue #513 buildClient reports reachability', () {
    test('a transport failure marks the network offline and the next answered '
        'request marks it online', () async {
      final reachability = NetworkReachability.forTesting();
      addTearDown(reachability.dispose);
      final client = await buildFakeClient(reachability);

      answer = _Answer.networkDown;
      await ping(client);
      expect(reachability.isOnline, isFalse);

      answer = _Answer.data;
      await ping(client);
      expect(reachability.isOnline, isTrue);
    });

    test('a GraphQL error answer never marks the network offline and counts '
        'as reachable', () async {
      final reachability = NetworkReachability.forTesting();
      addTearDown(reachability.dispose);
      final client = await buildFakeClient(reachability);

      answer = _Answer.graphQlError;
      await ping(client);
      expect(reachability.isOnline, isTrue);

      answer = _Answer.networkDown;
      await ping(client);
      expect(reachability.isOnline, isFalse);

      answer = _Answer.graphQlError;
      await ping(client);
      expect(reachability.isOnline, isTrue);
    });
  });
}
