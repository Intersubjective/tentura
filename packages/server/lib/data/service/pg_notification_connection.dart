import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart';

abstract interface class PgNotificationConnection {
  Stream<String> channel(String name);

  Future<void> listen(String channel);
  Future<void> notify(String channel, String payload);
  Future<void> close();
}

// The one-method interface is an intentional connection-construction seam.
// ignore: one_member_abstracts
abstract interface class PgNotificationConnector {
  Future<PgNotificationConnection> open(
    Endpoint endpoint, {
    required ConnectionSettings settings,
  });
}

@Singleton(as: PgNotificationConnector)
final class PostgresNotificationConnector implements PgNotificationConnector {
  const PostgresNotificationConnector();

  @override
  Future<PgNotificationConnection> open(
    Endpoint endpoint, {
    required ConnectionSettings settings,
  }) async => _PostgresNotificationConnection(
    await Connection.open(endpoint, settings: settings),
  );
}

final class _PostgresNotificationConnection
    implements PgNotificationConnection {
  const _PostgresNotificationConnection(this._connection);

  final Connection _connection;

  @override
  Stream<String> channel(String name) => _connection.channels[name];

  @override
  Future<void> listen(String channel) async {
    await _connection.execute('LISTEN ${_validatedChannel(channel)}');
  }

  @override
  Future<void> notify(String channel, String payload) =>
      _connection.channels.notify(_validatedChannel(channel), payload);

  @override
  Future<void> close() => _connection.close();

  static String _validatedChannel(String channel) {
    if (!RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(channel)) {
      throw ArgumentError.value(channel, 'channel', 'invalid PG channel');
    }
    return channel;
  }
}
