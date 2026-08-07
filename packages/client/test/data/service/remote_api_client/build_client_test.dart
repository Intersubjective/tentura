import 'dart:async';

import 'package:ferry/ferry.dart'
    show Client, DataSource, FetchPolicy, JsonOperationRequest, OperationResponse;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart' show parseString;
import 'package:gql_exec/gql_exec.dart' show Operation;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;

import 'package:tentura/data/service/remote_api_client/auth_loss_classifier.dart';
import 'package:tentura/data/service/remote_api_client/build_client.dart';
import 'package:tentura/domain/exception/generic_exception.dart';

void main() {
  const requestTimeout = Duration(milliseconds: 200);
  const waitPastTimeout = Duration(milliseconds: 400);

  late Completer<http.Response> neverCompletes;
  late http.Client hangingHttpClient;

  setUp(() {
    neverCompletes = Completer<http.Response>();
    hangingHttpClient = MockClient((_) => neverCompletes.future);
  });

  Future<Client> buildHangingClient() => buildClient(
    params: (
      apiEndpointUrl: 'https://example.test/api/v1/graphql',
      apiEndpointUrlV2: 'https://example.test/api/v2/graphql',
      userAgent: 'test',
      requestTimeout: requestTimeout,
    ),
    getToken: () async => null,
    httpClient: hangingHttpClient,
  );

  JsonOperationRequest operationRequest({
    required String operationName,
    required String document,
    Map<String, dynamic> vars = const {},
  }) => JsonOperationRequest(
    operation: Operation(
      document: parseString(document),
      operationName: operationName,
    ),
    fetchPolicy: FetchPolicy.NoCache,
    vars: vars,
  );

  group('buildClient transport timeout', () {
    test('non-upload operations fail with connectivity error instead of hanging',
        () async {
      final client = await buildHangingClient();
      final request = operationRequest(
        operationName: 'Ping',
        document: 'query Ping { __typename }',
      );

      final linkEvents = <Object?>[];
      final subscription = client
          .request(request)
          .where((event) => event.dataSource == DataSource.Link)
          .listen(
            linkEvents.add,
            onError: linkEvents.add,
          );

      await Future<void>.delayed(waitPastTimeout);
      await subscription.cancel();

      expect(
        linkEvents,
        isNotEmpty,
        reason: 'expected a link-level event within $waitPastTimeout',
      );

      final failure = linkEvents.single;
      if (failure is OperationResponse) {
        final response = failure;
        expect(response.hasErrors, isTrue);
        expect(
          mapRemoteFailure(response.linkException),
          isA<ConnectionUplinkException>(),
        );
      } else {
        expect(failure, isA<ConnectionUplinkException>());
      }
    });

    test('BeaconAddImage upload operations are not capped by transport timeout',
        () async {
      final client = await buildHangingClient();
      final request = operationRequest(
        operationName: 'BeaconAddImage',
        document: r'mutation BeaconAddImage($beaconId: String!) '
            r'{ BeaconAddImage(beaconId: $beaconId) }',
        vars: {'beaconId': 'b1'},
      );

      final linkEvents = <Object?>[];
      final subscription = client
          .request(request)
          .where((event) => event.dataSource == DataSource.Link)
          .listen(
            linkEvents.add,
            onError: linkEvents.add,
          );

      await Future<void>.delayed(waitPastTimeout);
      await subscription.cancel();

      expect(
        linkEvents,
        isEmpty,
        reason:
            'upload operation should remain pending past $requestTimeout, '
            'not time out',
      );
    });
  });
}
