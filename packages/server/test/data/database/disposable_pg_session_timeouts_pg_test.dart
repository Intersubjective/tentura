@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// Dart's default test timeout; a SQL-side wait must give up before it. Zero
/// means Postgres never gives up, so it is not a backstop either.
const _testTimeout = Duration(seconds: 30);

Future<Duration> _setting(Connection connection, String name) async {
  final rows = await connection.execute(
    Sql.named('SELECT setting::int FROM pg_settings WHERE name = @name'),
    parameters: {'name': name},
  );
  return Duration(milliseconds: rows.first.first! as int);
}

Future<List<String>> _databaseLocalDefaults(
  Connection admin,
  String databaseName,
) async {
  final rows = await admin.execute(
    Sql.named('''
SELECT unnest(s.setconfig)
FROM pg_db_role_setting s
JOIN pg_database d ON d.oid = s.setdatabase
WHERE d.datname = @name AND s.setrole = 0
'''),
    parameters: {'name': databaseName},
  );
  return [for (final row in rows) row.first! as String];
}

void expectSessionBackstops(Duration lock, Duration idle) {
  expect(lock, greaterThan(Duration.zero));
  expect(lock, lessThan(_testTimeout));
  expect(idle, greaterThan(Duration.zero));
  expect(idle, lessThan(_testTimeout));
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SESSION_TIMEOUTS_TEST_DB',
    defaultNamePrefix: 'tentura_test_session_timeouts',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  final opened = <Connection>[];
  Future<Connection> open(
    Endpoint endpoint,
    ConnectionSettings? settings,
  ) async {
    final connection = await Connection.open(endpoint, settings: settings);
    opened.add(connection);
    return connection;
  }

  Future<Connection> openTarget() => open(
    target.databaseEnv.pgEndpoint,
    target.databaseEnv.pgEndpointSettings,
  );
  Future<Connection> openAdmin() =>
      open(target.adminEnv.pgEndpoint, target.adminEnv.pgEndpointSettings);

  tearDown(() async {
    for (final connection in opened) {
      if (connection.isOpen) await connection.close();
    }
    opened.clear();
  });

  group('disposable database built by the writer setup', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
    });
    tearDownAll(() => tearDownDisposablePgWriter(session: session));

    test(
      'new sessions get a lock timeout and an idle-in-transaction timeout '
      'shorter than the test timeout',
      () async {
        final connection = await openTarget();

        expectSessionBackstops(
          await _setting(connection, 'lock_timeout'),
          await _setting(connection, 'idle_in_transaction_session_timeout'),
        );
      },
    );

    test('the defaults are stored on the database, not the cluster', () async {
      final admin = await openAdmin();

      final defaults = await _databaseLocalDefaults(admin, target.databaseName);

      expect(defaults, anyElement(startsWith('lock_timeout=')));
      expect(
        defaults,
        anyElement(startsWith('idle_in_transaction_session_timeout=')),
      );
      final clusterWide = await _setting(admin, 'lock_timeout');
      final local = await _setting(await openTarget(), 'lock_timeout');
      expect(
        clusterWide,
        isNot(local),
        reason: 'the admin database must keep the server default',
      );
    });
  });

  group('disposable database recreated from the template', () {
    final recreated = DisposablePgTarget.fromNamedEnvironment(
      envVarName: 'TENTURA_SESSION_TIMEOUTS_RECREATE_TEST_DB',
      defaultNamePrefix: 'tentura_test_session_timeouts_rc',
    );

    setUpAll(recreated.recreate);
    tearDownAll(recreated.drop);

    test('new sessions get the same backstops', () async {
      final connection = await open(
        recreated.databaseEnv.pgEndpoint,
        recreated.databaseEnv.pgEndpointSettings,
      );

      expectSessionBackstops(
        await _setting(connection, 'lock_timeout'),
        await _setting(connection, 'idle_in_transaction_session_timeout'),
      );
    });
  });
}
