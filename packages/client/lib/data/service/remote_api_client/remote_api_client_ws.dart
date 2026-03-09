import 'dart:async';
import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:web_socket_client/web_socket_client.dart';

import 'enum.dart';
import 'auth_box.dart';
import 'remote_api_client_base.dart';

base mixin RemoteApiClientWs on RemoteApiClientBase {
  // Finals
  final _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();

  final _stateController = StreamController<WebSocketState>.broadcast();

  // Vars
  Timer? _wsPingTimer;

  WebSocket? _webSocket;

  StreamSubscription<dynamic>? _messagesSubscription;

  StreamSubscription<ConnectionState>? _stateSubscription;

  WebSocketState _webSocketState = WebSocketState.disconnected;

  // Getters
  String get wsEndpointUrl;

  Duration get wsPingInterval;

  Stream<Map<String, dynamic>> get webSocketMessages =>
      _messagesController.stream;

  ///
  @override
  @mustCallSuper
  Future<String?> setAuth({
    required String seed,
    required AuthTokenFetcher authTokenFetcher,
    AuthRequestIntent? returnAuthRequestToken,
  }) async {
    _webSocket ??= WebSocket(Uri.parse(wsEndpointUrl).replace(scheme: 'wss'));
    _wsPingTimer ??= Timer.periodic(
      wsPingInterval,
      _onTimer,
    );
    _stateSubscription ??= _webSocket?.connection.listen(
      _onConnectionChanged,
      cancelOnError: false,
    );
    _messagesSubscription ??= _webSocket?.messages.listen(
      _onMessage,
      cancelOnError: false,
    );

    return super.setAuth(
      seed: seed,
      authTokenFetcher: authTokenFetcher,
      returnAuthRequestToken: returnAuthRequestToken,
    );
  }

  ///
  @override
  @mustCallSuper
  Future<void> dropAuth() async {
    await _dropAuth();
    return super.dropAuth();
  }

  ///
  @override
  @mustCallSuper
  Future<void> close() async {
    await _dropAuth();
    return super.close();
  }

  ///
  ///
  Stream<WebSocketState> get webSocketState async* {
    yield _webSocketState;
    yield* _stateController.stream;
  }

  ///
  ///
  void webSocketSend(dynamic message) {
    if (_webSocketState == WebSocketState.connected) {
      _webSocket?.send(message);
    }
  }

  //
  //
  Future<void> _dropAuth() async {
    _stateController.add(_webSocketState = WebSocketState.disconnected);
    _wsPingTimer?.cancel();
    _wsPingTimer = null;
    _webSocket?.send(
      '{"type":"auth","intent":"${AuthRequestIntent.cnameSignOut}"}',
    );
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    _webSocket?.close();
    _webSocket = null;
  }

  //
  //
  void _onTimer(_) {
    if (_webSocketState == WebSocketState.connected) {
      _webSocket?.send('{"type":"ping"}');
    }
  }

  //
  //
  Future<void> _onConnectionChanged(ConnectionState state) async {
    if (state is Connected || state is Reconnected) {
      _webSocket?.send(await _buildAuthMessage());
    } else {
      _stateController.add(_webSocketState = WebSocketState.disconnected);
    }
  }

  //
  //
  void _onMessage(dynamic messageRaw) {
    final message = switch (messageRaw) {
      final String m => jsonDecode(m),
      // final Uint8List m => messageRaw,
      _ => throw UnsupportedError('Unknown message format'),
    };

    if (message is Map<String, dynamic>) {
      switch (message['type']) {
        case 'pong':
          break;

        case 'auth':
          switch (message['intent']) {
            case AuthRequestIntent.cnameSignIn:
            case AuthRequestIntent.cnameSignUp:
              if (message['result'] == 'success') {
                _stateController.add(
                  _webSocketState = WebSocketState.connected,
                );
              }

            case AuthRequestIntent.cnameSignOut:
              _stateController.add(
                _webSocketState = WebSocketState.disconnected,
              );

            default:
          }

        default:
          _messagesController.add(message);
      }
    }
  }

  //
  //
  Future<String> _buildAuthMessage() async => jsonEncode({
    'type': 'auth',
    'intent': AuthRequestIntent.cnameSignIn,
    'token': (await getAuthToken()).accessToken,
  });
}
