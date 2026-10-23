import 'dart:async';

import 'package:ferry/ferry.dart'
    show
        Client,
        DataSource,
        FetchPolicy,
        JsonOperationRequest,
        OperationResponse;
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
    getToken: () async => 'test-token',
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
    test(
      'non-upload operations fail with a timeout, not an offline error, '
      'instead of hanging (#513)',
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
          final mapped = mapRemoteFailure(response.linkException);
          expect(mapped, isA<RequestTimeoutException>());
          expect(mapped, isNot(isA<ConnectionUplinkException>()));
        } else {
          expect(failure, isA<RequestTimeoutException>());
          expect(failure, isNot(isA<ConnectionUplinkException>()));
        }
      },
    );

    test(
      'a mutation whose answer is held past the timeout fails as a timeout, '
      'not offline, and is sent once (#513)',
      () async {
        final heldAnswer = Completer<http.Response>();
        var sends = 0;
        final client = await buildClient(
          params: (
            apiEndpointUrl: 'https://example.test/api/v1/graphql',
            apiEndpointUrlV2: 'https://example.test/api/v2/graphql',
            userAgent: 'test',
            requestTimeout: requestTimeout,
          ),
          getToken: () async => 'test-token',
          httpClient: MockClient((_) {
            sends++;
            return heldAnswer.future;
          }),
        );
        addTearDown(client.dispose);
        final request = operationRequest(
          operationName: 'RoomMessageCreate',
          document: 'mutation RoomMessageCreate { __typename }',
        );

        Object? failure;
        try {
          final response = await client
              .request(request)
              .where((event) => event.dataSource == DataSource.Link)
              .first
              .timeout(waitPastTimeout);
          failure = mapRemoteFailure(response.linkException);
        } on Object catch (e) {
          failure = e;
        }
        // The server saved it after all; its late answer must change nothing.
        heldAnswer.complete(
          http.Response(
            '{"data":{"__typename":"Mutation"}}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(failure, isA<RequestTimeoutException>());
        expect(failure, isNot(isA<ConnectionUplinkException>()));
        expect(sends, 1);
      },
    );

    test(
      'BeaconAddImage upload operations are not capped by transport timeout',
      () async {
        final client = await buildHangingClient();
        final request = operationRequest(
          operationName: 'BeaconAddImage',
          document:
              r'mutation BeaconAddImage($beaconId: String!) '
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
      },
    );
  });

  group('RemoteApiClient outer timeout (My Work spinner regression)', () {
    // Reproduces the bug behind the My Work "infinite spinner": when ferry's
    // own RequestControllerTypedLink never triggers the underlying fetch
    // (executeOnListen: false pins this down deterministically — in
    // production the trigger was some other, unreproduced condition upstream
    // of our custom `link` chain), the request stream just sits open
    // forever. It never reaches `_TimeoutLink`, so that cap never arms and
    // the caller hangs past its own timeout. `RemoteApiClient.request` guards
    // against exactly this by wrapping `client.request(...)` in a second,
    // outer `.timeout()` — this test proves that wrapper (reproduced inline,
    // since `_gqlClient` in `RemoteApiClient` is private and not test-seamed)
    // recovers where `_TimeoutLink` alone does not.
    test(
      'a request ferry never triggers still fails instead of hanging forever',
      () async {
        final client = await buildClient(
          params: (
            apiEndpointUrl: 'https://example.test/api/v1/graphql',
            apiEndpointUrlV2: 'https://example.test/api/v2/graphql',
            userAgent: 'test',
            requestTimeout: requestTimeout,
          ),
          getToken: () async => 'test-token',
          // Never actually invoked: the point is that ferry never forwards
          // the request down to the link chain at all.
          httpClient: MockClient((_) async {
            fail('the link chain should never be reached');
          }),
        );

        final request = JsonOperationRequest(
          operation: Operation(
            document: parseString('query Ping { __typename }'),
            operationName: 'Ping',
          ),
          fetchPolicy: FetchPolicy.NoCache,
          vars: const {},
          executeOnListen: false,
        );

        // `_TimeoutLink` alone (i.e. `client.request` with no outer wrapper)
        // never sees an event, because the request never reaches it.
        final untimedEvents = <Object?>[];
        final untimedSub = client
            .request(request)
            .listen(
              untimedEvents.add,
              onError: untimedEvents.add,
            );
        await Future<void>.delayed(waitPastTimeout);
        await untimedSub.cancel();
        expect(
          untimedEvents,
          isEmpty,
          reason:
              '_TimeoutLink should not have fired: the request never '
              'reached the link chain',
        );

        // The outer timeout `RemoteApiClient.request` adds — reproduced here
        // — recovers regardless.
        Object? outerFailure;
        try {
          await client
              .request(request)
              .timeout(
                requestTimeout,
                onTimeout: (sink) => sink.addError(
                  mapRemoteFailure(
                    TimeoutException(
                      'GraphQL request timed out',
                      requestTimeout,
                    ),
                  ),
                ),
              )
              .first;
        } catch (e) {
          outerFailure = e;
        }

        expect(outerFailure, isA<RequestTimeoutException>());
      },
    );
  });

  group('V2 direct routing', () {
    test('BeaconThreadsList routes to Tentura V2', () {
      expect(isTenturaDirectOperation('BeaconThreadsList'), isTrue);
    });

    test('MarkThreadSeen routes to Tentura V2', () {
      expect(isTenturaDirectOperation('MarkThreadSeen'), isTrue);
    });

    test('candidate context open and Retry each use only V2', () async {
      final paths = <String>[];
      final client = await buildClient(
        params: (
          apiEndpointUrl: 'https://example.test/api/v1/graphql',
          apiEndpointUrlV2: 'https://example.test/api/v2/graphql',
          userAgent: 'test',
          requestTimeout: requestTimeout,
        ),
        getToken: () async => 'test-token',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            '{"data":{"forwardCandidateContext":'
            '{"status":"longPath","nodes":[]}}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final request = operationRequest(
        operationName: 'ForwardCandidateContextFetch',
        document: r'''
          query ForwardCandidateContextFetch(
            $candidateId: String!,
            $context: String!
          ) {
            forwardCandidateContext(
              candidateId: $candidateId,
              context: $context
            ) { status nodes { kind id displayName } }
          }
        ''',
        vars: const {'candidateId': 'U2', 'context': 'personal'},
      );

      await client
          .request(request)
          .firstWhere((event) => event.dataSource == DataSource.Link);
      expect(paths, ['/api/v2/graphql']);

      await client
          .request(request)
          .firstWhere((event) => event.dataSource == DataSource.Link);
      expect(paths, ['/api/v2/graphql', '/api/v2/graphql']);
      expect(paths.where((path) => path == '/api/v1/graphql'), isEmpty);
    });
  });
}
