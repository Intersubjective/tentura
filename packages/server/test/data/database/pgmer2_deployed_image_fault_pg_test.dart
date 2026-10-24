// pgmer2 connector faults against the PostgreSQL image compose.prod.yaml
// deploys (tentura-ev3z.13, review §7 step 8): a MeritRank peer that never
// answers (blackhole), answers one byte at a time (trickle), or whose call is
// cancelled from another session must end within the deployed
// MERITRANK_RECV_TIMEOUT_MSEC whole-call budget (cancel: at once), and leave
// the SQL connection usable.
//
// Each case runs a private copy of the deployed image (no volumes) against a
// private fault peer: the shared MeritRank container is not touched. Needs
// Docker; tagged `mr` so it runs in the serialized local MeritRank run, never
// beside other suites. It exercises pgmer2 as shipped and changes nothing in it.
@Tags(['pg', 'mr', 'repo-files'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart' show isPgTestsRequired;

Directory _repoRoot() {
  var directory = Directory.current.absolute;
  while (!File('${directory.path}/compose.prod.yaml').existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('repository root not found');
    }
    directory = parent;
  }
  return directory;
}

/// The `postgres` service block of compose.prod.yaml.
String _postgresService() {
  final lines = File(
    '${_repoRoot().path}/compose.prod.yaml',
  ).readAsStringSync().split('\n');
  final start = lines.indexOf('  postgres:');
  if (start < 0) throw StateError('compose.prod.yaml has no postgres service');
  var end = start + 1;
  while (end < lines.length && !RegExp(r'^(  \S|\S)').hasMatch(lines[end])) {
    end++;
  }
  return lines.sublist(start + 1, end).join('\n');
}

Future<ProcessResult> _docker(List<String> arguments) => Process.run(
  'docker',
  arguments,
).timeout(const Duration(minutes: 5));

// A private MeritRank stand-in. Reads requests without replying for
// blackhole/cancel. For trickle it sends a valid length header, then an
// incomplete body one byte per 100 ms, so every receive makes progress and
// only the whole-call deadline can end the call.
final class _FaultPeer {
  _FaultPeer(this.server, this.fault, this.budgetMs) {
    server.listen((socket) {
      sockets.add(socket);
      var startedReply = false;
      socket.listen(
        (request) {
          if (request.isEmpty) return;
          if (!receivedRequest.isCompleted) receivedRequest.complete();
          if (fault != 'trickle' || startedReply) return;
          startedReply = true;
          final bodyLength = max(256, budgetMs ~/ 100 + 100);
          socket.add([
            (bodyLength >> 24) & 255,
            (bodyLength >> 16) & 255,
            (bodyLength >> 8) & 255,
            bodyLength & 255,
          ]);
          timers.add(
            Timer.periodic(const Duration(milliseconds: 100), (_) {
              socket.add([0]);
              trickledBytes++;
            }),
          );
        },
        onError: (Object _) {},
      );
    });
  }

  final ServerSocket server;
  final String fault;
  final int budgetMs;
  final receivedRequest = Completer<void>();
  final sockets = <Socket>[];
  final timers = <Timer>[];
  int trickledBytes = 0;

  Future<void> close() async {
    for (final timer in timers) {
      timer.cancel();
    }
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
  }
}

// Measured 2026-10-22 (tentura-ev3z.13, docs/performance/db-capacity-tuning.md):
// on postgres-tentura:v0.9.1 neither a silent nor a trickling peer ends the
// call at the budget (still waiting at 20 s; a paused real MeritRank still at
// 70 s+), while cancel ends it within 1 s. Owner decision pending; the server
// bounds request-path calls with statement_timeout/cancel meanwhile.
const _deadlineNotHonoured =
    'pgmer2 v0.9.1 does not end a blackholed/trickled call at '
    'MERITRANK_RECV_TIMEOUT_MSEC (tentura-ev3z.13 finding); un-skip once the '
    'deployed image bounds it';

Future<void> main() async {
  final service = _postgresService();
  final image = RegExp(
    r'^    image:\s*(\S+)',
    multiLine: true,
  ).firstMatch(service)!.group(1)!.replaceAll(RegExp('[\'"]'), '');
  final budgetMs = int.parse(
    RegExp(
      r'MERITRANK_RECV_TIMEOUT_MSEC=(\d+)',
    ).firstMatch(service)!.group(1)!,
  );

  String? skip;
  try {
    var inspect = await _docker(['image', 'inspect', image]);
    if (inspect.exitCode != 0) await _docker(['pull', image]);
    inspect = await _docker(['image', 'inspect', image]);
    if (inspect.exitCode != 0) skip = 'image $image unavailable';
  } on Object catch (error) {
    skip = 'docker unavailable: $error';
  }
  if (skip != null && isPgTestsRequired()) {
    throw StateError('pgmer2 fault test required but $skip');
  }

  group('pgmer2 on the deployed image $image', () {
    test('ships a bounded whole-call budget', () {
      expect(budgetMs, inInclusiveRange(1, 30000));
    });

    for (final fault in ['blackhole', 'trickle', 'cancel']) {
      test(
        '$fault ends within the budget and leaves the connection usable',
        () => _probe(image: image, fault: fault, budgetMs: budgetMs),
        timeout: const Timeout(Duration(minutes: 3)),
        skip: fault == 'cancel' ? null : _deadlineNotHonoured,
      );
    }
  }, skip: skip);
}

Future<void> _probe({
  required String image,
  required String fault,
  required int budgetMs,
}) async {
  final peer = _FaultPeer(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    fault,
    budgetMs,
  );
  addTearDown(peer.close);
  final reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = reservation.port;
  await reservation.close();
  final nonce = Random.secure().nextInt(1 << 32).toRadixString(16);
  final name = 'tentura-pgmer2-probe-$pid-$nonce';
  final password = 'probe-$nonce';
  // Registered before launch: an interrupted start must not leave a container.
  addTearDown(() => _docker(['rm', '--force', '--volumes', name]));
  final run = await _docker([
    'run',
    '--detach',
    '--rm',
    '--name',
    name,
    '--network',
    'host',
    '--env',
    'POSTGRES_PASSWORD=$password',
    '--env',
    'MERITRANK_SERVICE_URL=tcp://127.0.0.1:${peer.server.port}',
    '--env',
    'MERITRANK_RECV_TIMEOUT_MSEC=$budgetMs',
    image,
    'postgres',
    '-p',
    '$port',
    '-c',
    'listen_addresses=127.0.0.1',
  ]);
  expect(run.exitCode, 0, reason: '${run.stderr}');

  final readyUntil = DateTime.now().add(const Duration(seconds: 60));
  while (true) {
    final ready = await _docker([
      'exec',
      name,
      'pg_isready',
      '-h',
      '127.0.0.1',
      '-U',
      'postgres',
      '-p',
      '$port',
    ]);
    if (ready.exitCode == 0) break;
    expect(
      DateTime.now().isBefore(readyUntil),
      isTrue,
      reason: 'probe PostgreSQL did not start: ${ready.stderr}',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  final endpoint = Endpoint(
    host: '127.0.0.1',
    port: port,
    database: 'postgres',
    username: 'postgres',
    password: password,
  );
  final settings = ConnectionSettings(
    sslMode: SslMode.disable,
    queryTimeout: Duration(milliseconds: budgetMs + 10000),
  );
  Connection? worker;
  for (var attempt = 0; worker == null; attempt++) {
    try {
      worker = await Connection.open(endpoint, settings: settings);
    } on Object {
      // The entrypoint restarts the server once after initdb.
      if (attempt > 50) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  final sql = worker;
  addTearDown(() => sql.close(force: true));
  final control = await Connection.open(endpoint, settings: settings);
  addTearDown(() => control.close(force: true));
  await sql.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
  // Neither a statement timeout nor the client's query timeout may stand in
  // for pgmer2's own deadline.
  await sql.execute('SET statement_timeout = 0');
  final backend = (await sql.execute('SELECT pg_backend_pid()')).single.single;

  final elapsed = Stopwatch()..start();
  // mr_sync always performs an RPC; no cache can answer it.
  final outcome = sql
      .execute('SELECT mr_sync()')
      .then<Object?>((_) => null, onError: (Object error) => error);
  await peer.receivedRequest.future.timeout(const Duration(seconds: 10));
  // Another session stays responsive while the call waits.
  expect((await control.execute('SELECT 1')).single.single, 1);
  if (fault == 'cancel') {
    elapsed.reset();
    final cancelled = await control.execute(
      Sql.named('SELECT pg_cancel_backend(@pid)'),
      parameters: {'pid': backend},
    );
    expect(cancelled.single.single, isTrue);
  }
  final error = await outcome.timeout(Duration(milliseconds: budgetMs + 3000));
  elapsed.stop();
  printOnFailure('$fault: ${elapsed.elapsedMilliseconds} ms, $error');

  expect(error, isA<ServerException>(), reason: 'must fail in the server');
  if (fault == 'cancel') {
    expect((error! as ServerException).code, '57014');
    expect(elapsed.elapsedMilliseconds, lessThanOrEqualTo(1000));
  } else {
    expect('$error', contains('deadline exceeded'));
    expect(
      elapsed.elapsedMilliseconds,
      inInclusiveRange(max(0, budgetMs - 500), budgetMs + 1000),
    );
  }
  if (fault == 'trickle') {
    expect(peer.trickledBytes, greaterThan(1));
  }
  // The same connection is still usable after the connector failure.
  expect((await sql.execute('SELECT 1')).single.single, 1);
}
