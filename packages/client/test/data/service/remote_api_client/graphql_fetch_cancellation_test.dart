import 'dart:async';
import 'dart:convert';

import 'package:ferry/ferry.dart' show Client;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart' show parseString;
import 'package:gql_exec/gql_exec.dart';
import 'package:http/http.dart' as http;
import 'package:tentura/data/service/remote_api_client/build_client.dart';

const _observationBudget = Duration(milliseconds: 500);

void main() {
  late _RecordingHttpClient transport;
  late Client client;
  final subscriptions = <StreamSubscription<Response>>[];

  Future<void> build({
    Duration timeout = const Duration(seconds: 10),
    Future<String?> Function()? getToken,
  }) async {
    transport = _RecordingHttpClient();
    client = await buildClient(
      params: (
        apiEndpointUrl: 'https://example.test/api/v1/graphql',
        apiEndpointUrlV2: 'https://example.test/api/v2/graphql',
        userAgent: 'fetch-cancellation-test',
        requestTimeout: timeout,
      ),
      getToken: getToken ?? () async => 'test-token',
      httpClient: transport,
    );
    addTearDown(() async {
      // Complete the fake network before awaiting async* cancellation. An
      // uncancellable production request must fail an assertion, not hang
      // teardown in [CancellableDedupeLink]'s internal first-response subscriber.
      transport.respondToAll();
      for (final subscription in subscriptions) {
        await subscription.cancel().timeout(const Duration(seconds: 2));
      }
      subscriptions.clear();
      await client.dispose();
      transport.close();
    });
  }

  StreamSubscription<Response> listen(
    Request request, {
    void Function(Response)? onData,
    void Function(Object)? onError,
  }) {
    final subscription = client.link
        .request(request)
        .listen(
          onData ?? (_) {},
          onError: onError ?? (Object _) {},
        );
    subscriptions.add(subscription);
    return subscription;
  }

  group('GraphQL fetch cancellation', () {
    for (final operation in ['Ping', 'ConstellationFieldFetch']) {
      test('$operation supplies an abort trigger to the HTTP client', () async {
        await build();
        listen(_request(operation));
        final exchange = await transport.exchangeAt(0);

        expect(exchange.request, isA<http.AbortableRequest>());
        expect(
          (exchange.request as http.AbortableRequest).abortTrigger,
          isNotNull,
          reason: 'Both Hasura and direct V2 requests must abort fetch.',
        );
      });

      test('$operation aborts fetch when its last subscriber leaves', () async {
        await build();
        final subscription = listen(_request(operation));
        final exchange = await transport.exchangeAt(0);

        // cancel() on the current async* transport waits for the response.
        // Observe the network independently rather than await that response.
        unawaited(subscription.cancel());
        final aborted = await _completesWithin(exchange.aborted.future);

        expect(
          aborted,
          isTrue,
          reason: 'Leaving the screen must stop the underlying HTTP request.',
        );
      });
    }

    test('a request deadline aborts fetch and rejects late data', () async {
      await build(timeout: const Duration(milliseconds: 100));
      final errors = <Object>[];
      final responses = <Response>[];
      final timedOut = Completer<void>();
      listen(
        _request('ConstellationFieldFetch'),
        onData: responses.add,
        onError: (error) {
          errors.add(error);
          if (!timedOut.isCompleted) timedOut.complete();
        },
      );
      final exchange = await transport.exchangeAt(0);
      await timedOut.future.timeout(const Duration(seconds: 2));
      final aborted = await _completesWithin(exchange.aborted.future);
      exchange.respond();
      await _drainMicrotasks();

      expect(errors, isNotEmpty);
      expect(
        aborted,
        isTrue,
        reason: 'Reporting a stream timeout must also abort the fetch.',
      );
      expect(
        responses,
        isEmpty,
        reason: 'A deadline is terminal for its caller.',
      );
    });

    test(
      'deduplicated fetch aborts only after every consumer leaves',
      () async {
        await build();
        final request = _request('ConstellationFieldFetch');
        final first = listen(request);
        final second = listen(request);
        final exchange = await transport.exchangeAt(0);
        await _drainMicrotasks();
        expect(transport.exchanges, hasLength(1));

        unawaited(first.cancel());
        await _drainMicrotasks();
        expect(
          exchange.aborted.isCompleted,
          isFalse,
          reason: 'The remaining consumer still owns the shared fetch.',
        );

        expect(
          await _completesWithin(exchange.aborted.future),
          isFalse,
          reason:
              'Cancelling one consumer must leave the shared fetch active '
              'through asynchronous cancellation cleanup.',
        );
        expect(
          exchange.response.isCompleted,
          isFalse,
          reason: 'The remaining consumer is still waiting for the response.',
        );

        unawaited(second.cancel());
        expect(
          await _completesWithin(exchange.aborted.future),
          isTrue,
          reason: 'Dedupe bookkeeping must not keep an abandoned fetch alive.',
        );
        expect(transport.exchanges, hasLength(1));
      },
    );

    test('cancelling during token refresh never sends GraphQL', () async {
      final refresh = Completer<String?>();
      final refreshing = Completer<void>();
      await build(
        getToken: () {
          refreshing.complete();
          return refresh.future;
        },
      );
      final responses = <Response>[];
      final subscription = listen(_request('Ping'), onData: responses.add);
      await refreshing.future;
      unawaited(subscription.cancel());
      await _drainMicrotasks();
      refresh.complete('refreshed-token');
      await _drainMicrotasks();
      transport.respondToAll();

      expect(
        transport.exchanges,
        isEmpty,
        reason: 'An abandoned auth waiter must not start network work.',
      );
      expect(responses, isEmpty);
    });

    test('a deadline during token refresh prevents a later fetch', () async {
      final refresh = Completer<String?>();
      final refreshing = Completer<void>();
      final timedOut = Completer<void>();
      await build(
        timeout: const Duration(milliseconds: 100),
        getToken: () {
          refreshing.complete();
          return refresh.future;
        },
      );
      listen(
        _request('Ping'),
        onError: (_) {
          if (!timedOut.isCompleted) timedOut.complete();
        },
      );
      await refreshing.future;
      await timedOut.future.timeout(const Duration(seconds: 2));
      refresh.complete('refreshed-token');
      await _drainMicrotasks();
      transport.respondToAll();

      expect(
        transport.exchanges,
        isEmpty,
        reason: 'Auth refresh spends the original request deadline.',
      );
    });

    test('one cancelled waiter preserves the shared token refresh', () async {
      final refresh = Completer<String?>();
      final bothWaiting = Completer<void>();
      Future<String?>? sharedRefresh;
      var waiters = 0;
      var refreshStarts = 0;
      await build(
        getToken: () {
          if (sharedRefresh == null) {
            refreshStarts++;
            sharedRefresh = refresh.future;
          }
          if (++waiters == 2) bothWaiting.complete();
          return sharedRefresh!;
        },
      );
      final first = listen(_request('Ping', consumer: 'leaving'));
      final survivorResponse = Completer<Response>();
      listen(
        _request('Ping', consumer: 'staying'),
        onData: survivorResponse.complete,
      );
      await bothWaiting.future;
      unawaited(first.cancel());
      await _drainMicrotasks();
      refresh.complete('shared-refreshed-token');
      await _drainMicrotasks();
      transport.respondToAll();
      await survivorResponse.future.timeout(const Duration(seconds: 2));

      expect(refreshStarts, 1);
      expect(transport.exchanges, hasLength(1));
      expect(transport.exchanges.single.payload['variables'], {
        'consumer': 'staying',
      });
      expect(
        transport.exchanges.single.request.headers['Authorization'],
        'Bearer shared-refreshed-token',
      );
    });
  });
}

Request _request(String operation, {String? consumer}) => Request(
  operation: Operation(
    document: parseString('query $operation { __typename }'),
    operationName: operation,
  ),
  variables: consumer == null ? const {} : {'consumer': consumer},
);

Future<bool> _completesWithin(Future<void> future) => future
    .then((_) => true)
    .timeout(_observationBudget, onTimeout: () => false);

Future<void> _drainMicrotasks() async {
  for (var turn = 0; turn < 5; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _RecordingHttpClient extends http.BaseClient {
  final exchanges = <_Exchange>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final payload =
        jsonDecode(await request.finalize().bytesToString())
            as Map<String, dynamic>;
    final exchange = _Exchange(request, payload);
    exchanges.add(exchange);
    if (request is http.Abortable) {
      unawaited(
        request.abortTrigger?.then((_) {
          exchange.aborted.complete();
          if (!exchange.response.isCompleted) {
            exchange.response.completeError(
              http.RequestAbortedException(request.url),
            );
          }
        }),
      );
    }
    return exchange.response.future;
  }

  Future<_Exchange> exchangeAt(int index) async {
    final clock = Stopwatch()..start();
    while (exchanges.length <= index) {
      if (clock.elapsed > const Duration(seconds: 2)) {
        fail('GraphQL did not reach the injected HTTP client.');
      }
      await Future<void>.delayed(Duration.zero);
    }
    return exchanges[index];
  }

  void respondToAll() {
    for (final exchange in exchanges) {
      exchange.respond();
    }
  }

  @override
  void close() => respondToAll();
}

final class _Exchange {
  _Exchange(this.request, this.payload);

  final http.BaseRequest request;
  final Map<String, dynamic> payload;
  final aborted = Completer<void>();
  final response = Completer<http.StreamedResponse>();

  void respond() {
    if (response.isCompleted) return;
    response.complete(
      http.StreamedResponse(
        Stream.value(utf8.encode('{"data":{"__typename":"query_root"}}')),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
  }
}
