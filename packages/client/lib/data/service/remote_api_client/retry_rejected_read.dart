import 'dart:async';
import 'dart:math';

import 'package:ferry/ferry.dart' show OperationRequest, OperationResponse;
import 'package:gql/ast.dart' show OperationDefinitionNode, OperationType;

import 'package:tentura/domain/exception/generic_exception.dart';

import 'auth_loss_classifier.dart';

/// Total tries of a read the server turned away with its admission backoff.
const _maxAttempts = 3;

const _maxJitterMs = 100;

final _jitter = Random();

/// True for a read, the only kind of operation that is safe to re-send.
bool isReadOperation(OperationRequest<dynamic, dynamic> request) => request
    .operation
    .document
    .definitions
    .whereType<OperationDefinitionNode>()
    .every((d) => d.type == OperationType.query);

/// Re-opens [open] after the advertised delay (plus a little jitter) while it
/// fails with the server admission backoff, up to [_maxAttempts] tries; the
/// outcome of the last try is surfaced as is. The rejection is swallowed
/// until then, so it reaches neither the user nor Sentry.
Stream<OperationResponse<TData, TVars>> retryRejectedRead<TData, TVars>(
  Stream<OperationResponse<TData, TVars>> Function() open,
) {
  final controller = StreamController<OperationResponse<TData, TVars>>();
  var cancelled = false;
  StreamIterator<OperationResponse<TData, TVars>>? responses;
  Timer? retryTimer;
  Completer<void>? retryDelay;

  Future<void> pump() async {
    for (var attempt = 1; !cancelled; attempt++) {
      final isLast = attempt == _maxAttempts;
      Duration? wait;
      try {
        final iterator = responses = StreamIterator(open());
        while (await iterator.moveNext()) {
          if (cancelled) return;
          final response = iterator.current;
          wait = isLast ? null : _busyHint(response);
          if (wait != null) break;
          controller.add(response);
        }
      } on Object catch (error, stackTrace) {
        if (cancelled) return;
        wait = isLast ? null : _busyHintOf(error);
        if (wait == null) {
          controller.addError(error, stackTrace);
        }
      } finally {
        await responses?.cancel();
        responses = null;
      }
      if (cancelled || wait == null) break;
      final delay = retryDelay = Completer<void>();
      retryTimer = Timer(
        wait + Duration(milliseconds: _jitter.nextInt(_maxJitterMs)),
        delay.complete,
      );
      await delay.future;
      retryDelay = null;
      retryTimer = null;
    }
    if (!cancelled) await controller.close();
  }

  controller
    ..onListen = pump
    ..onCancel = () {
      cancelled = true;
      retryTimer?.cancel();
      final delay = retryDelay;
      if (delay != null && !delay.isCompleted) delay.complete();
      // Cancel the source immediately, but complete in the caller's zone.
      // StreamIterator can return a root-zone future that stalls firstWhere.
      unawaited(responses?.cancel());
      return Future<void>.value();
    };
  return controller.stream;
}

Duration? _busyHint(OperationResponse<dynamic, dynamic> response) =>
    response.hasErrors
    ? _busyHintOf(response.linkException ?? response.graphqlErrors)
    : null;

Duration? _busyHintOf(Object? failure) {
  final mapped = mapRemoteFailure(failure);
  if (mapped is! RemoteApiRetryLaterException) return null;
  return mapped.retryAfter;
}
