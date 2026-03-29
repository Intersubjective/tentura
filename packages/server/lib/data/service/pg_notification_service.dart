import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart';

import 'package:tentura_server/env.dart';

/// Maintains a dedicated Postgres connection for LISTEN/NOTIFY.
///
/// Pools cannot hold LISTEN state, so this service opens a single
/// long-lived connection per isolate.
@singleton
class PgNotificationService {
  @factoryMethod
  static Future<PgNotificationService> create(Env env) async {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.execute('LISTEN p2p_chat');
    return PgNotificationService._(connection);
  }

  PgNotificationService._(this._connection);

  final Connection _connection;

  /// Stream of payloads arriving on the `p2p_chat` channel.
  Stream<String> get notifications => _connection.channels['p2p_chat'];

  /// Send a NOTIFY on the given channel with the given payload.
  Future<void> notify(String channel, String payload) =>
      _connection.channels.notify(channel, payload);

  @disposeMethod
  Future<void> dispose() => _connection.close();
}
