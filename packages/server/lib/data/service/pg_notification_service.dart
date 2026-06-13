import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

import 'package:tentura_server/env.dart';

/// Maintains a dedicated Postgres connection for LISTEN/NOTIFY.
///
/// Pools cannot hold LISTEN state, so this service opens a single
/// long-lived connection per isolate. A supervisor reconnects with
/// exponential backoff if the connection drops.
@singleton
class PgNotificationService {
  PgNotificationService._(this._env);

  static final _log = Logger('PgNotificationService');

  final Env _env;
  final _controller = StreamController<String>.broadcast();

  Connection? _connection;
  StreamSubscription<String>? _sub;
  int _reconnectAttempts = 0;
  bool _disposed = false;
  bool _reconnectScheduled = false;

  @factoryMethod
  static Future<PgNotificationService> create(Env env) async {
    final svc = PgNotificationService._(env);
    await svc._connect();
    return svc;
  }

  /// Stream of payloads arriving on the `entity_changes` channel.
  Stream<String> get entityChangeNotifications => _controller.stream;

  /// Send a NOTIFY on the given channel with the given payload.
  Future<void> notify(String channel, String payload) {
    final conn = _connection;
    if (conn == null) {
      throw StateError('No active PG notification connection');
    }
    return conn.channels.notify(channel, payload);
  }

  Future<void> _connect() async {
    final conn = await Connection.open(
      _env.pgEndpoint,
      settings: _env.pgEndpointSettings,
    );
    await conn.execute('LISTEN entity_changes');
    _connection = conn;
    _sub = conn.channels['entity_changes'].listen(
      _controller.add,
      onError: (Object e, StackTrace st) {
        _log.severe('[PgNotificationService] Channel error', e, st);
        _scheduleReconnect();
      },
      onDone: () {
        if (!_disposed) {
          _log.warning('[PgNotificationService] Connection closed unexpectedly');
          _scheduleReconnect();
        }
      },
    );
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    // A single dropped connection fires both `onError` and `onDone`; guard
    // against scheduling overlapping reconnect timers (which would open
    // duplicate connections and reset backoff).
    if (_reconnectScheduled) return;
    _reconnectScheduled = true;
    final delay = Duration(seconds: (1 << _reconnectAttempts).clamp(1, 60));
    _reconnectAttempts++;
    _log.info(
      '[PgNotificationService] Reconnecting in ${delay.inSeconds}s '
      '(attempt $_reconnectAttempts)',
    );
    Future.delayed(delay, () async {
      _reconnectScheduled = false;
      if (_disposed) return;
      try {
        await _sub?.cancel();
        await _connection?.close();
        _connection = null;
        await _connect();
        _reconnectAttempts = 0;
        _log.info('[PgNotificationService] Reconnected');
      } catch (e, st) {
        _log.severe('[PgNotificationService] Reconnect failed', e, st);
        _scheduleReconnect();
      }
    });
  }

  @disposeMethod
  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    await _connection?.close();
    await _controller.close();
  }
}
