@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// The room reply readback suite runs inside the full server-pg run, where
/// Postgres is shared with many other suites and every round trip is slow.
/// Cases that build a long room must finish inside Dart's default per-test
/// timeout whatever the database latency is, so seeding such a room has to cost
/// a bounded number of round trips rather than one per message.
///
/// Each test here runs ONE case of that suite in a child `dart test` process
/// (default 30 s per-test timeout) whose connections to its database go
/// through a proxy that adds latency to every client-to-server write. That
/// models a slow database without looking at what is being sent, so it does not
/// care whether statements are batched, pipelined or prepared.
const _readbackSuite =
    'test/data/repository/room_message_reply_readback_pg_test.dart';

/// The per-test timeout the child must run under: Dart's own default, pinned so
/// an ambient config cannot loosen it.
const _defaultTestTimeout = '30s';

/// Latency added to every client-to-server write on the suite's connections.
/// Seeding a 50-message room one statement at a time pays this 50 times, which
/// alone is past [_defaultTestTimeout].
const _roundTripLatency = Duration(milliseconds: 700);

/// Forwards TCP to Postgres. Connections whose startup packet names the target
/// database get [_roundTripLatency] added to every client write; all other
/// connections (the admin/template ones used for setup) are untouched.
class _SlowDatabaseProxy {
  _SlowDatabaseProxy._(
    this._server,
    this._upstreamHost,
    this._upstreamPort,
    this._slowDatabase,
  );

  final ServerSocket _server;
  final String _upstreamHost;
  final int _upstreamPort;
  final String _slowDatabase;
  final _sockets = <Socket>[];

  /// Client writes that were delayed.
  int slowedWrites = 0;

  int get port => _server.port;

  static Future<_SlowDatabaseProxy> start({
    required String upstreamHost,
    required int upstreamPort,
    required String slowDatabase,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = _SlowDatabaseProxy._(
      server,
      upstreamHost,
      upstreamPort,
      slowDatabase,
    );
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
          .then<void>((_) {}, onError: (_) {})
          .whenComplete(client.destroy),
    );

    var pending = Future<void>.value();
    // The first packet is the protocol startup message, which carries
    // `database\0<name>\0` in plain text (SSL is disabled for test targets).
    var slow = false;
    var first = true;
    client.listen(
      (chunk) {
        if (first) {
          first = false;
          slow = latin1
              .decode(chunk)
              .contains('database\u0000$_slowDatabase\u0000');
        }
        final delay = slow;
        if (delay) slowedWrites++;
        pending = pending.then((_) async {
          if (delay) await Future<void>.delayed(_roundTripLatency);
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

/// Outcome of one test of the child run.
class _ChildOutcome {
  _ChildOutcome(this.name, {required this.passed, required this.skipped});

  final String name;
  final bool passed;
  final bool skipped;
}

List<_ChildOutcome> _parseOutcomes(String jsonReporterOutput) {
  final names = <int, String>{};
  final outcomes = <_ChildOutcome>[];
  for (final line in jsonReporterOutput.split('\n')) {
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
      outcomes.add(
        _ChildOutcome(
          names[event['testID']] ?? '${event['testID']}',
          passed: event['result'] == 'success',
          skipped: event['skipped'] == true,
        ),
      );
    }
  }
  return outcomes;
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_REPLY_READBACK_SLOW_DB_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_reply_slow',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('reply readback cases that seed a 50-message room', () {
    // Every case of the suite that seeds a long room. Each one is its own test
    // so an unrelated failure elsewhere in the suite cannot turn this red.
    for (final caseName in const [
      'parent outside the 50-row window still resolves in list snapshot',
      'parent author off the message page still populates replyToAuthorTitle',
    ]) {
      test(
        'finish within the default test timeout on a slow database: $caseName',
        () async {
          final upstreamHost =
              Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
          final upstreamPort =
              int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
          final proxy = await _SlowDatabaseProxy.start(
            upstreamHost: upstreamHost,
            upstreamPort: upstreamPort,
            slowDatabase: target.databaseName,
          );
          addTearDown(proxy.close);

          final result = await Process.run(
            Platform.resolvedExecutable,
            [
              'test',
              _readbackSuite,
              '--plain-name',
              caseName,
              '--timeout',
              _defaultTestTimeout,
              '--reporter',
              'json',
              '-j',
              '1',
            ],
            // Credentials and pool size are inherited so the child behaves as
            // it would in CI; only the endpoint and database name differ.
            environment: {
              'POSTGRES_HOST': '127.0.0.1',
              'POSTGRES_PORT': '${proxy.port}',
              'TENTURA_ROOM_REPLY_READBACK_PG_TEST_DB': target.databaseName,
            },
          );

          final outcomes = _parseOutcomes(result.stdout.toString());
          final ours = outcomes.where((o) => o.name.endsWith(caseName));
          final detail = '${result.stdout}\n${result.stderr}';

          expect(
            ours,
            hasLength(1),
            reason:
                'The child must have run exactly the targeted case.\n'
                '$detail',
          );
          expect(
            ours.single.skipped,
            isFalse,
            reason: 'The case must really run, not skip.\n$detail',
          );
          expect(
            proxy.slowedWrites,
            greaterThan(0),
            reason:
                'The child never reached its database through the slow proxy, '
                'so this run does not model a loaded database.\n$detail',
          );
          expect(
            ours.single.passed,
            isTrue,
            reason:
                '"$caseName" did not finish within $_defaultTestTimeout when '
                'every database round trip takes $_roundTripLatency '
                '(${proxy.slowedWrites} slowed writes).\n$detail',
          );
        },
        skip: skipReason,
        // Outer bound only: child setup plus the case's own 30 s.
        timeout: const Timeout(Duration(minutes: 4)),
      );
    }
  });
}
