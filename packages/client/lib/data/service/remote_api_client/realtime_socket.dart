import 'package:injectable/injectable.dart';
import 'package:web_socket_client/web_socket_client.dart' as web_socket;

enum RealtimeSocketConnectionState {
  connecting,
  connected,
  reconnecting,
  reconnected,
  disconnected,
}

abstract interface class RealtimeSocket {
  Stream<RealtimeSocketConnectionState> get connection;
  Stream<Object?> get messages;

  void send(Object message);
  Future<void> close();
}

// The one-method interface is intentional: tests must replace socket creation.
// ignore: one_member_abstracts
abstract interface class RealtimeSocketFactory {
  RealtimeSocket create(Uri uri);
}

@Singleton(as: RealtimeSocketFactory)
final class WebSocketClientRealtimeSocketFactory
    implements RealtimeSocketFactory {
  const WebSocketClientRealtimeSocketFactory();

  @override
  RealtimeSocket create(Uri uri) => _WebSocketClientRealtimeSocket(uri);
}

final class _WebSocketClientRealtimeSocket implements RealtimeSocket {
  _WebSocketClientRealtimeSocket(Uri uri) : _socket = web_socket.WebSocket(uri);

  final web_socket.WebSocket _socket;

  @override
  Stream<RealtimeSocketConnectionState> get connection =>
      _socket.connection.map(
        (state) => switch (state) {
          web_socket.Connecting() => RealtimeSocketConnectionState.connecting,
          web_socket.Connected() => RealtimeSocketConnectionState.connected,
          web_socket.Reconnecting() =>
            RealtimeSocketConnectionState.reconnecting,
          web_socket.Reconnected() => RealtimeSocketConnectionState.reconnected,
          web_socket.Disconnecting() || web_socket.Disconnected() =>
            RealtimeSocketConnectionState.disconnected,
        },
      );

  @override
  Stream<Object?> get messages => _socket.messages;

  @override
  void send(Object message) => _socket.send(message);

  @override
  Future<void> close() async => _socket.close();
}
