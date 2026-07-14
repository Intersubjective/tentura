import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import 'package:tentura_root/domain/enums.dart' show WebSocketState;

import 'auth_box.dart';
import 'realtime_socket.dart';
import 'realtime_transport_status.dart';
import 'remote_api_client_base.dart';

base mixin RemoteApiClientWs on RemoteApiClientBase {
  final _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<WebSocketState>.broadcast();
  final _transportStatusController =
      StreamController<RealtimeTransportStatus>.broadcast();
  final _minClientVersionController = StreamController<String>.broadcast();
  final _logger = Logger('RemoteApiClientWs');
  final _random = Random();

  String? _lastEmittedMinClientVersion;
  String? _boundAccountId;
  int _connectionEpoch = 0;
  int? _activeSocketEpoch;
  int _authFailures = 0;
  int _supervisorFailures = 0;
  bool _reconstructing = false;
  bool _disposed = false;

  Timer? _pingTimer;
  Timer? _authDeadlineTimer;
  Timer? _authRetryTimer;
  Timer? _socketReplacementTimer;
  DateTime? _lastPongAt;

  RealtimeSocket? _webSocket;
  StreamSubscription<Object?>? _messagesSubscription;
  StreamSubscription<RealtimeSocketConnectionState>? _stateSubscription;

  WebSocketState _webSocketState = WebSocketState.disconnected;
  RealtimeTransportStatus _transportStatus =
      const RealtimeTransportStatus.unbound(connectionEpoch: 0);

  String get wsEndpointUrl;
  Duration get wsPingInterval;
  RealtimeSocketFactory get realtimeSocketFactory;

  @visibleForTesting
  Duration get realtimeAuthAcknowledgementTimeout =>
      const Duration(seconds: 10);

  @visibleForTesting
  Duration get realtimeRetryBaseDelay => const Duration(milliseconds: 250);

  @visibleForTesting
  Duration get realtimeRetryMaxDelay => const Duration(seconds: 10);

  @visibleForTesting
  int get realtimeRetryJitterMilliseconds => 250;

  @visibleForTesting
  Duration get realtimePongTimeout => Duration(
    microseconds: max(
      const Duration(seconds: 10).inMicroseconds,
      wsPingInterval.inMicroseconds * 3,
    ),
  );

  Stream<Map<String, dynamic>> get webSocketMessages =>
      _messagesController.stream;

  Stream<String> get minClientVersionStream =>
      _minClientVersionController.stream;

  String? get realtimeAccountId => _boundAccountId;

  Stream<RealtimeTransportStatus> get realtimeTransportStatus async* {
    yield _transportStatus;
    yield* _transportStatusController.stream;
  }

  Stream<WebSocketState> get webSocketState async* {
    yield _webSocketState;
    yield* _stateController.stream;
  }

  /// Starts realtime only after an auth flow has returned its authoritative ID.
  Future<void> bindRealtimeAccount(String accountId) async {
    if (accountId.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }
    if (_disposed) {
      throw StateError('RemoteApiClientWs is disposed');
    }
    if (_boundAccountId == accountId && _webSocket != null) {
      return;
    }

    await _teardownSocket(sendSignOut: _boundAccountId != null);
    _boundAccountId = accountId;
    _authFailures = 0;
    _supervisorFailures = 0;
    await _startSocket(RealtimeReconnectCause.initial);
  }

  Future<void> unbindRealtimeAccount() async {
    _boundAccountId = null;
    _activeSocketEpoch = null;
    _connectionEpoch++;
    await _teardownSocket(sendSignOut: true);
    _emitTransportStatus(
      RealtimeTransportStatus.unbound(connectionEpoch: _connectionEpoch),
    );
  }

  @override
  @mustCallSuper
  Future<void> dropAuth() async {
    await unbindRealtimeAccount();
    await super.dropAuth();
  }

  @override
  @mustCallSuper
  Future<void> close() async {
    await unbindRealtimeAccount();
    await super.close();
    if (_disposed) return;
    _disposed = true;
    await _messagesController.close();
    await _stateController.close();
    await _transportStatusController.close();
    await _minClientVersionController.close();
  }

  void webSocketSend(Object message) {
    if (_transportStatus.phase == RealtimeTransportPhase.authenticated) {
      _webSocket?.send(message);
    }
  }

  Future<void> _startSocket(RealtimeReconnectCause cause) async {
    final accountId = _boundAccountId;
    if (accountId == null || _disposed) return;

    final wsUri = Uri.parse(wsEndpointUrl);
    final socket = realtimeSocketFactory.create(
      wsUri.replace(scheme: wsUri.scheme == 'https' ? 'wss' : 'ws'),
    );
    final epoch = ++_connectionEpoch;
    _activeSocketEpoch = epoch;
    _webSocket = socket;
    _lastPongAt = null;
    _emitTransportStatus(
      RealtimeTransportStatus(
        accountId: accountId,
        connectionEpoch: epoch,
        phase: RealtimeTransportPhase.connecting,
        cause: cause,
      ),
    );

    _stateSubscription = socket.connection.listen(
      (state) => _onConnectionChanged(state, epoch, cause),
      onError: (Object error, StackTrace stackTrace) {
        _logger.fine('Realtime socket connection error', error, stackTrace);
      },
      onDone: () => _onSocketDone(epoch),
      cancelOnError: false,
    );
    _messagesSubscription = socket.messages.listen(
      (message) => _onMessage(message, epoch, cause),
      onError: (Object error, StackTrace stackTrace) {
        _logger.fine('Realtime socket message error', error, stackTrace);
      },
      cancelOnError: false,
    );
  }

  void _onConnectionChanged(
    RealtimeSocketConnectionState state,
    int epoch,
    RealtimeReconnectCause cause,
  ) {
    if (!_isCurrentEpoch(epoch)) return;
    switch (state) {
      case RealtimeSocketConnectionState.connected:
        unawaited(_authenticate(epoch, cause));
      case RealtimeSocketConnectionState.reconnected:
        unawaited(_authenticate(epoch, RealtimeReconnectCause.network));
      case RealtimeSocketConnectionState.connecting:
      case RealtimeSocketConnectionState.reconnecting:
        _emitBoundStatus(
          epoch: epoch,
          phase: RealtimeTransportPhase.connecting,
          cause: RealtimeReconnectCause.network,
        );
      case RealtimeSocketConnectionState.disconnected:
        _stopAuthenticatedTimers();
        _emitBoundStatus(
          epoch: epoch,
          phase: RealtimeTransportPhase.disconnected,
          cause: RealtimeReconnectCause.network,
        );
    }
  }

  Future<void> _authenticate(
    int epoch,
    RealtimeReconnectCause cause,
  ) async {
    if (!_isCurrentEpoch(epoch)) return;
    _authRetryTimer?.cancel();
    _authDeadlineTimer?.cancel();
    _emitBoundStatus(
      epoch: epoch,
      phase: RealtimeTransportPhase.authenticating,
      cause: cause,
    );
    _authDeadlineTimer = Timer(
      realtimeAuthAcknowledgementTimeout,
      () => _handleAuthenticationFailure(
        epoch,
        cause,
        TimeoutException('Realtime authentication acknowledgement timed out'),
      ),
    );

    try {
      final message = await _buildAuthMessage();
      if (!_isCurrentEpoch(epoch)) return;
      _webSocket?.send(message);
    } on Object catch (error, stackTrace) {
      _logger.fine(
        'Realtime authentication frame construction failed',
        error,
        stackTrace,
      );
      _handleAuthenticationFailure(epoch, cause, error);
    }
  }

  void _handleAuthenticationFailure(
    int epoch,
    RealtimeReconnectCause cause,
    Object error,
  ) {
    if (!_isCurrentEpoch(epoch)) return;
    _authDeadlineTimer?.cancel();
    _authRetryTimer?.cancel();
    _authFailures++;
    if (_authFailures >= 3) {
      _logger.warning('Realtime authentication repeatedly failed', error);
      unawaited(
        _reconstructSocket(RealtimeReconnectCause.authenticationFailure),
      );
      return;
    }

    _authRetryTimer = Timer(_retryDelay(_authFailures), () {
      if (_isCurrentEpoch(epoch)) {
        unawaited(_authenticate(epoch, cause));
      }
    });
  }

  void _onMessage(
    Object? messageRaw,
    int epoch,
    RealtimeReconnectCause cause,
  ) {
    if (!_isCurrentEpoch(epoch)) return;
    final message = _decodeMessage(messageRaw);
    if (message == null) return;

    switch (message['type']) {
      case 'pong':
        _lastPongAt = DateTime.timestamp();
        final raw = message['min_client_version'];
        if (raw is String &&
            raw.isNotEmpty &&
            raw != _lastEmittedMinClientVersion) {
          _lastEmittedMinClientVersion = raw;
          if (!_minClientVersionController.isClosed) {
            _minClientVersionController.add(raw);
          }
        }

      case 'auth':
        if (message['intent'] == AuthRequestIntent.cnameSignOut) {
          _stopAuthenticatedTimers();
          _emitBoundStatus(
            epoch: epoch,
            phase: RealtimeTransportPhase.disconnected,
            cause: cause,
          );
          return;
        }
        if (message['result'] == 'success') {
          _onAuthenticated(epoch, cause);
        } else {
          _handleAuthenticationFailure(
            epoch,
            cause,
            StateError('Realtime authentication rejected'),
          );
        }

      default:
        if (message['error'] != null &&
            _transportStatus.phase == RealtimeTransportPhase.authenticating) {
          _handleAuthenticationFailure(
            epoch,
            cause,
            StateError('Realtime authentication error'),
          );
          return;
        }
        if (!_messagesController.isClosed) {
          _messagesController.add(message);
        }
    }
  }

  void _onAuthenticated(int epoch, RealtimeReconnectCause cause) {
    if (!_isCurrentEpoch(epoch)) return;
    _authDeadlineTimer?.cancel();
    _authRetryTimer?.cancel();
    _authFailures = 0;
    _supervisorFailures = 0;
    _lastPongAt = DateTime.timestamp();
    _emitBoundStatus(
      epoch: epoch,
      phase: RealtimeTransportPhase.authenticated,
      cause: cause,
    );
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      wsPingInterval,
      (_) => _onPingTimer(epoch),
    );
  }

  void _onPingTimer(int epoch) {
    if (!_isCurrentEpoch(epoch) ||
        _transportStatus.phase != RealtimeTransportPhase.authenticated) {
      return;
    }
    final lastPongAt = _lastPongAt;
    if (lastPongAt != null &&
        DateTime.timestamp().difference(lastPongAt) >= realtimePongTimeout) {
      unawaited(_reconstructSocket(RealtimeReconnectCause.pongTimeout));
      return;
    }
    _webSocket?.send('{"type":"ping"}');
  }

  void _onSocketDone(int epoch) {
    if (!_isCurrentEpoch(epoch) || _socketReplacementTimer != null) return;
    _stopAuthenticatedTimers();
    _emitBoundStatus(
      epoch: epoch,
      phase: RealtimeTransportPhase.disconnected,
      cause: RealtimeReconnectCause.terminalSocket,
    );
    _supervisorFailures++;
    _socketReplacementTimer = Timer(_retryDelay(_supervisorFailures), () {
      _socketReplacementTimer = null;
      if (_isCurrentEpoch(epoch)) {
        unawaited(_reconstructSocket(RealtimeReconnectCause.terminalSocket));
      }
    });
  }

  Future<void> _reconstructSocket(RealtimeReconnectCause cause) async {
    if (_reconstructing || _boundAccountId == null || _disposed) return;
    _reconstructing = true;
    try {
      _activeSocketEpoch = null;
      await _teardownSocket(sendSignOut: false);
      if (_boundAccountId != null && !_disposed) {
        await _startSocket(cause);
      }
    } finally {
      _reconstructing = false;
    }
  }

  Future<void> _teardownSocket({required bool sendSignOut}) async {
    _stopAuthenticatedTimers();
    _authRetryTimer?.cancel();
    _authRetryTimer = null;
    _socketReplacementTimer?.cancel();
    _socketReplacementTimer = null;

    final socket = _webSocket;
    _webSocket = null;
    if (sendSignOut &&
        socket != null &&
        _transportStatus.phase == RealtimeTransportPhase.authenticated) {
      socket.send(
        '{"type":"auth","intent":"${AuthRequestIntent.cnameSignOut}"}',
      );
    }
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    await socket?.close();
  }

  void _stopAuthenticatedTimers() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _authDeadlineTimer?.cancel();
    _authDeadlineTimer = null;
  }

  void _emitBoundStatus({
    required int epoch,
    required RealtimeTransportPhase phase,
    required RealtimeReconnectCause cause,
  }) {
    final accountId = _boundAccountId;
    if (accountId == null || !_isCurrentEpoch(epoch)) return;
    _emitTransportStatus(
      RealtimeTransportStatus(
        accountId: accountId,
        connectionEpoch: epoch,
        phase: phase,
        cause: cause,
      ),
    );
  }

  void _emitTransportStatus(RealtimeTransportStatus status) {
    if (status == _transportStatus) return;
    _transportStatus = status;
    if (!_transportStatusController.isClosed) {
      _transportStatusController.add(status);
    }

    final nextWebSocketState =
        status.phase == RealtimeTransportPhase.authenticated
        ? WebSocketState.connected
        : WebSocketState.disconnected;
    if (nextWebSocketState != _webSocketState && !_stateController.isClosed) {
      _stateController.add(_webSocketState = nextWebSocketState);
    }
  }

  bool _isCurrentEpoch(int epoch) =>
      !_disposed &&
      _boundAccountId != null &&
      _activeSocketEpoch == epoch &&
      _webSocket != null;

  Duration _retryDelay(int attempt) {
    final exponent = min(max(attempt - 1, 0), 6);
    final baseMicros = realtimeRetryBaseDelay.inMicroseconds * (1 << exponent);
    final cappedMicros = min(
      baseMicros,
      realtimeRetryMaxDelay.inMicroseconds,
    );
    final jitterMicros = realtimeRetryJitterMilliseconds <= 0
        ? 0
        : _random.nextInt(realtimeRetryJitterMilliseconds + 1) * 1000;
    return Duration(microseconds: cappedMicros + jitterMicros);
  }

  Map<String, dynamic>? _decodeMessage(Object? messageRaw) {
    if (messageRaw is! String) {
      _logger.fine('Ignored non-string realtime frame');
      return null;
    }
    try {
      final decoded = jsonDecode(messageRaw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on Object catch (error, stackTrace) {
      _logger.fine('Ignored malformed realtime frame', error, stackTrace);
      return null;
    }
  }

  Future<String> _buildAuthMessage() async => jsonEncode({
    'type': 'auth',
    'intent': AuthRequestIntent.cnameSignIn,
    'token': (await getAuthToken()).accessToken,
  });
}
