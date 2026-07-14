import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import 'package:tentura_server/env.dart';

import 'pg_notification_connection.dart';

final class PgNotificationRecovery {
  const PgNotificationRecovery({required this.sequence});

  final int sequence;
}

/// Maintains one dedicated Postgres LISTEN connection per server isolate.
@singleton
class PgNotificationService {
  PgNotificationService._(
    this._env,
    this._connector,
    this._reconnectDelay,
  );

  static final _log = Logger('PgNotificationService');
  static const _channel = 'entity_changes';

  final Env _env;
  final PgNotificationConnector _connector;
  final Duration Function(int attempt) _reconnectDelay;
  final _controller = StreamController<String>.broadcast();
  final _recoveryController =
      StreamController<PgNotificationRecovery>.broadcast();

  PgNotificationConnection? _connection;
  StreamSubscription<String>? _sub;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int _recoverySequence = 0;
  bool _disposed = false;
  bool _reconnectScheduled = false;

  @factoryMethod
  static Future<PgNotificationService> create(
    Env env,
    PgNotificationConnector connector,
  ) async {
    final service = PgNotificationService._(
      env,
      connector,
      (attempt) => Duration(seconds: (1 << attempt).clamp(1, 60)),
    );
    await service._connect(isRecovery: false);
    return service;
  }

  @visibleForTesting
  static Future<PgNotificationService> createForTesting(
    Env env,
    PgNotificationConnector connector, {
    Duration reconnectDelay = Duration.zero,
  }) async {
    final service = PgNotificationService._(
      env,
      connector,
      (_) => reconnectDelay,
    );
    await service._connect(isRecovery: false);
    return service;
  }

  Stream<String> get entityChangeNotifications => _controller.stream;

  /// Emits once after a failed LISTEN connection has been replaced.
  /// Initial startup deliberately emits nothing.
  Stream<PgNotificationRecovery> get recoveryNotifications =>
      _recoveryController.stream;

  Future<void> notify(String channel, String payload) {
    final connection = _connection;
    if (connection == null) {
      throw StateError('No active PG notification connection');
    }
    return connection.notify(channel, payload);
  }

  Future<void> _connect({required bool isRecovery}) async {
    final connection = await _connector.open(
      _env.pgEndpoint,
      settings: _env.pgEndpointSettings,
    );
    await connection.listen(_channel);
    _connection = connection;
    _sub = connection
        .channel(_channel)
        .listen(
          _controller.add,
          onError: (Object error, StackTrace stackTrace) {
            _log.severe(
              '[PgNotificationService] Channel error',
              error,
              stackTrace,
            );
            _scheduleReconnect();
          },
          onDone: () {
            if (!_disposed) {
              _log.warning(
                '[PgNotificationService] Connection closed unexpectedly',
              );
              _scheduleReconnect();
            }
          },
        );
    if (isRecovery && !_recoveryController.isClosed) {
      _recoveryController.add(
        PgNotificationRecovery(sequence: ++_recoverySequence),
      );
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectScheduled) return;
    _reconnectScheduled = true;
    final delay = _reconnectDelay(_reconnectAttempts);
    _reconnectAttempts++;
    _log.info(
      '[PgNotificationService] Reconnecting in ${delay.inMilliseconds}ms '
      '(attempt $_reconnectAttempts)',
    );
    _reconnectTimer = Timer(delay, () => unawaited(_reconnect()));
  }

  Future<void> _reconnect() async {
    _reconnectScheduled = false;
    if (_disposed) return;
    try {
      await _sub?.cancel();
      await _connection?.close();
      _connection = null;
      await _connect(isRecovery: true);
      _reconnectAttempts = 0;
      _log.info('[PgNotificationService] Reconnected');
    } on Object catch (error, stackTrace) {
      _log.severe(
        '[PgNotificationService] Reconnect failed',
        error,
        stackTrace,
      );
      _scheduleReconnect();
    }
  }

  @disposeMethod
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _connection?.close();
    await _controller.close();
    await _recoveryController.close();
  }
}
