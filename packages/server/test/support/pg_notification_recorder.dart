import 'dart:async';
import 'dart:convert';

/// Records decoded `entity_changes` payloads and offers notification barriers.
class PgNotificationRecorder {
  PgNotificationRecorder(Stream<String> source) {
    _subscription = source.listen(_onPayload);
  }

  final messages = <Map<String, dynamic>>[];

  late final StreamSubscription<String> _subscription;
  String? _barrierToken;
  Completer<void>? _barrierSeen;
  var _barrierCounter = 0;

  void _onPayload(String payload) {
    final message = jsonDecode(payload) as Map<String, dynamic>;
    if (message['entity'] == 'barrier') {
      if (message['id'] == _barrierToken) {
        _barrierSeen?.complete();
      }
      return;
    }
    messages.add(message);
  }

  /// Sends a barrier through [sendBarrier] and waits until it is delivered on
  /// the same channel; all notifications received until then are dropped.
  Future<void> drain({
    required Future<void> Function(String token) sendBarrier,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await flush(sendBarrier: sendBarrier, timeout: timeout);
    messages.clear();
  }

  /// Waits until all notifications preceding the barrier have been recorded.
  ///
  /// Send the barrier on the same connection that performed the writes, after
  /// committing them. Unlike [drain], this preserves the recorded payloads.
  Future<void> flush({
    required Future<void> Function(String token) sendBarrier,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final token = 'drain-${_barrierCounter++}';
    final seen = Completer<void>();
    _barrierToken = token;
    _barrierSeen = seen;
    try {
      await sendBarrier(token);
      await seen.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Notification barrier $token was not delivered',
          timeout,
        ),
      );
    } finally {
      _barrierToken = null;
      _barrierSeen = null;
    }
  }

  Future<void> cancel() => _subscription.cancel();
}
