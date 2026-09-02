import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

/// Create a WebSocket connection.
Future<WebSocket> connect(
  String url, {
  Iterable<String>? protocols,
  Map<String, dynamic>? headers,
  Duration? pingInterval,
  String? binaryType,
}) async {
  final socket = WebSocket(
    url,
    protocols?.map((e) => e.toJS).toList().toJS ?? JSArray(),
  )
    // Either "blob" (default) or "arraybuffer".
    // https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/binaryType
    ..binaryType = binaryType ?? 'blob';

  if (socket.readyState == 1) return socket;

  final completer = Completer<WebSocket>();

  // Tentura workaround — remove when
  // https://github.com/felangel/web_socket_client/pull/87 is merged+released:
  // on web, open then error can both fire for the same connect attempt;
  // completing twice throws StateError.
  unawaited(
    socket.onOpen.first.then((_) {
      if (!completer.isCompleted) completer.complete(socket);
    }),
  );

  unawaited(
    socket.onError.first.then((event) {
      if (completer.isCompleted) return;
      final error =
          event.isA<ErrorEvent>() ? (event as ErrorEvent).error : null;
      completer.completeError(error ?? Exception('unknown error'));
    }),
  );

  return completer.future;
}
