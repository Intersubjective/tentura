@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// The `constellation_field` hint producers suite runs inside the full
/// server-pg run, where Postgres is shared with many other suites and every
/// round trip is slow. Whether the producers emit one marker per trust change
/// must not depend on how quickly the database answers.
///
/// This test reproduces that load: it runs the producers suite in a child
/// `dart test` process whose database connection goes through a proxy that
/// adds latency to every statement touching `user_trust_edge`, then asserts the
/// whole suite still passes.
const _producersSuite =
    'test/data/database/constellation_field_hint_producers_pg_test.dart';

/// Added per statement on `user_trust_edge`. The suite writes trust edges in a
/// burst, so the latency adds up to far more than any fixed wall-clock budget
/// a test could reasonably put on that burst (the loaded full run took ~74 s).
const _writeLatency = Duration(milliseconds: 150);

/// The proxy must have injected at least this much delay in total, otherwise
/// the run does not model a loaded database and a pass proves nothing.
const _minInjectedDelay = Duration(seconds: 10);

const _slowTable = 'user_trust_edge';

/// Forwards TCP to Postgres and delays client-to-server traffic that carries
/// SQL mentioning `user_trust_edge`.
class _SlowWritePostgresProxy {
  _SlowWritePostgresProxy._(
    this._server,
    this._upstreamHost,
    this._upstreamPort,
  );

  final ServerSocket _server;
  final String _upstreamHost;
  final int _upstreamPort;
  final _sockets = <Socket>[];
  int delayedStatements = 0;

  int get port => _server.port;

  static Future<_SlowWritePostgresProxy> start({
    required String upstreamHost,
    required int upstreamPort,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = _SlowWritePostgresProxy._(server, upstreamHost, upstreamPort);
    server.listen(proxy._handle);
    return proxy;
  }

  Future<void> _handle(Socket client) async {
    final Socket upstream;
    try {
      upstream = await Socket.connect(_upstreamHost, _upstreamPort);
    } on Object {
      client.destroy();
      return;
    }
    _sockets
      ..add(client)
      ..add(upstream);
    unawaited(
      client
          .addStream(upstream)
          .catchError((_) {})
          .whenComplete(
            client.destroy,
          ),
    );

    var pending = Future<void>.value();
    // SQL text can straddle two TCP chunks; keep the tail of the previous
    // chunk so a table name split across them is still recognised, and delay
    // only on the chunk that completes the match.
    var tail = '';
    client.listen(
      (chunk) {
        final text = latin1.decode(chunk);
        final window = tail + text;
        final slow = window.contains(_slowTable) && !tail.contains(_slowTable);
        tail = window.substring(
          window.length > _slowTable.length - 1
              ? window.length - (_slowTable.length - 1)
              : 0,
        );
        if (slow) delayedStatements++;
        pending = pending.then((_) async {
          if (slow) await Future<void>.delayed(_writeLatency);
          upstream.add(chunk);
        });
      },
      onDone: () => pending.then((_) => upstream.destroy()),
      onError: (_) => upstream.destroy(),
      cancelOnError: true,
    );
  }

  Future<void> close() async {
    await _server.close();
    for (final socket in _sockets) {
      socket.destroy();
    }
  }
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_FIELD_HINT_SLOW_DB_TEST_DB',
    defaultNamePrefix: 'tentura_test_cfhint_slow',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  test(
    'hint producers still emit one marker per change when the database is '
    'slow to answer writes',
    () async {
      final upstreamHost = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
      final upstreamPort =
          int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
      final proxy = await _SlowWritePostgresProxy.start(
        upstreamHost: upstreamHost,
        upstreamPort: upstreamPort,
      );
      addTearDown(proxy.close);

      final result = await Process.run(
        Platform.resolvedExecutable,
        ['test', _producersSuite, '--reporter', 'json', '-j', '1'],
        // Everything else (credentials, DB naming, pool size, ...) is inherited
        // from this process so the child behaves exactly as it would in CI.
        environment: {
          'POSTGRES_HOST': '127.0.0.1',
          'POSTGRES_PORT': '${proxy.port}',
        },
      );

      final failed = <String>[];
      var passed = 0;
      var skipped = 0;
      final names = <int, String>{};
      for (final line in result.stdout.toString().split('\n')) {
        if (line.isEmpty) continue;
        final Object? event;
        try {
          event = jsonDecode(line);
        } on FormatException {
          continue;
        }
        if (event is! Map<String, dynamic>) continue;
        final test = event['test'];
        if (event['type'] == 'testStart' && test is Map<String, dynamic>) {
          names[test['id'] as int] = test['name'] as String;
        }
        if (event['type'] == 'testDone' && event['hidden'] != true) {
          final name = names[event['testID']] ?? '${event['testID']}';
          if (event['skipped'] == true) {
            skipped++;
          } else if (event['result'] == 'success') {
            passed++;
          } else {
            failed.add(name);
          }
        }
      }

      expect(
        _writeLatency * proxy.delayedStatements,
        greaterThanOrEqualTo(_minInjectedDelay),
        reason:
            "The proxy must actually have slowed the suite's writes, "
            'otherwise this run does not model a loaded database.\n'
            '${result.stderr}',
      );
      expect(skipped, 0, reason: 'The suite must really run, not skip.');
      expect(
        failed,
        isEmpty,
        reason: 'Producer tests failed against a slow database: $failed',
      );
      expect(passed, greaterThanOrEqualTo(6));
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
