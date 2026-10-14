import 'dart:async';

import 'package:ferry/ferry.dart' show Link, NextLink;
import 'package:gql_exec/gql_exec.dart';
import 'package:http/http.dart' as http;

/// A shared fetch owns its abort trigger, rather than any single consumer.
class FetchCancellation extends ContextEntry {
  static final _zoneKey = Object();
  final _abort = Completer<void>();

  static FetchCancellation? get current =>
      Zone.current[_zoneKey] as FetchCancellation?;

  Future<void> get abortTrigger => _abort.future;

  void cancel() {
    if (!_abort.isCompleted) _abort.complete();
  }

  void check() {
    if (_abort.isCompleted) throw http.RequestAbortedException();
  }

  @override
  List<Object> get fieldsForEquality => [this];
}

/// No bookkeeping subscriber keeps an abandoned fetch alive: the broadcast
/// source is cancelled by its last caller.
class CancellableDedupeLink extends Link {
  final _inFlight = <Request, Stream<Response>>{};

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    return _inFlight.putIfAbsent(request, () {
      late Stream<Response> shared;
      void remove() {
        if (identical(_inFlight[request], shared)) _inFlight.remove(request);
      }

      return shared = forward!(request)
          .transform(
            StreamTransformer<Response, Response>.fromHandlers(
              handleData: (response, sink) {
                // A delivered response must not be reused by a later retry.
                remove();
                sink.add(response);
              },
              handleDone: (sink) {
                remove();
                sink.close();
              },
            ),
          )
          .asBroadcastStream(
            onCancel: (subscription) {
              remove();
              unawaited(subscription.cancel());
            },
          );
    });
  }
}

/// Abort immediately, even while auth is waiting for a shared token refresh.
class FetchCancellationLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final cancellation = FetchCancellation();
    StreamSubscription<Response>? subscription;
    late StreamController<Response> controller;
    controller = StreamController<Response>(
      onListen: () {
        runZoned(
          () {
            subscription =
                forward!(
                  request.withContextEntry(cancellation),
                ).listen(
                  controller.add,
                  onError: controller.addError,
                  onDone: controller.close,
                );
          },
          zoneValues: {FetchCancellation._zoneKey: cancellation},
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        cancellation.cancel();
        // The caller already left; a late abort error has no consumer.
        return subscription?.cancel().catchError((Object _) {});
      },
    );
    return controller.stream;
  }
}

/// Retain HttpLink's serialization while supplying http 1.6 abort triggers.
class AbortableGraphqlHttpClient extends http.BaseClient {
  AbortableGraphqlHttpClient(this._client);

  final http.Client _client;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final cancellation = FetchCancellation.current;
    cancellation?.check();
    final http.BaseRequest abortable;
    if (request is http.Request) {
      abortable = http.AbortableRequest(
        request.method,
        request.url,
        abortTrigger: cancellation?.abortTrigger,
      )..bodyBytes = request.bodyBytes;
    } else if (request is http.MultipartRequest) {
      abortable =
          http.AbortableMultipartRequest(
              request.method,
              request.url,
              abortTrigger: cancellation?.abortTrigger,
            )
            ..fields.addAll(request.fields)
            ..files.addAll(request.files);
    } else {
      return _client.send(request);
    }
    abortable
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
    return _client.send(abortable);
  }

  @override
  void close() => _client.close();
}
