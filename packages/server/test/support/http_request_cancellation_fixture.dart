import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Middleware;
import 'package:tentura_server/api/middleware/auth_middleware.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/app/workers/web_worker.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import 'disposable_pg_target.dart';
import 'pg_test_public_keys.dart';
import 'pg_wait.dart';
import 'session_database_di_harness.dart';

const cancellationActor = 'U00000000ca11';
const cancellationLockKey = 73120481;
const cancellationCommitKey = 73120482;

const _create = r'''
mutation CreateWithCancellation($title: String, $clientOpId: String) {
  beaconCreate(
    title: $title
    description: "Cancellation acceptance probe"
    clientOpId: $clientOpId
  ) { id }
}
''';

/// Test-only barriers surround real authentication and SQL. No barrier
/// cancels work itself: serveWeb, RootRouter, repositories and the real pool
/// must propagate the downstream disconnect through an actual Caddy process.
final class HttpRequestCancellationFixture {
  HttpRequestCancellationFixture(this.target);

  final DisposablePgTarget target;
  late DisposablePgWriterSession session;
  late _PausingAuthMiddleware _auth;
  late _ProbingBeaconRepository _beacons;
  late Uri origin;
  late String _bearer;
  late Process _caddy;
  late Directory _directory;
  late Future<void> _worker;
  late SendPort _stopWorker;
  late ReceivePort _workerMessages;
  late StreamSubscription<dynamic> _workerSubscription;
  late Future<int> _caddyExit;
  final _caddyOutput = StringBuffer();
  final _calls = <CancellationHttpCall>[];

  Connection get writer => session.writer;
  MainDbPool get pool => getIt.get<MainDbPool>();

  static Future<String?> caddySkipReason() async {
    try {
      final result = await Process.run('caddy', ['version']);
      if (result.exitCode == 0) return null;
      return 'Caddy is unavailable: ${result.stderr}';
    } on ProcessException catch (error) {
      return 'Caddy is unavailable: $error';
    }
  }

  Future<void> start() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    await writer.execute(
      Sql.named('''
        INSERT INTO public."user" (id, display_name, public_key)
        VALUES (@id, 'Cancellation viewer', @key)
        ON CONFLICT (id) DO NOTHING
      '''),
      parameters: {
        'id': cancellationActor,
        'key': pgTestPublicKey('cancellation', 1),
      },
    );
    await _installSqlBarriers();

    final upstreamPort = await _unusedPort();
    final proxyPort = await _unusedPort();
    final base = target.databaseEnv;
    final env = Env(
      environment: Environment.dev,
      printEnv: false,
      isDebugModeOn: false,
      bindAddress: '127.0.0.1',
      listenWebPort: upstreamPort,
      serverUri: Uri.parse('http://127.0.0.1:$proxyPort'),
      publicOrigin: 'http://127.0.0.1:$proxyPort',
      publicKey: Env.kJwtPublicKey,
      privateKey: Env.kJwtPrivateKey,
      pgHost: base.pgHost,
      pgPort: base.pgPort,
      pgDatabase: base.pgDatabase,
      pgUsername: base.pgUsername,
      pgPassword: base.pgPassword,
      maxConnectionCount: 1,
      maxConnectionAge: 3600,
      pgStatementTimeoutMs: 30000,
      beaconCreateMaxPerUser: 1000,
      sentryDsn: '',
    );

    // Match the existing DI fixture's background-I/O stubs. Authentication
    // still delegates to the real AuthMiddleware after an optional barrier.
    getIt
      ..registerLazySingleton<AuthMiddleware>(
        () => _PausingAuthMiddleware(
          getIt.get<AuthCase>(),
          getIt.get<SessionCase>(),
        ),
      )
      ..registerLazySingleton<BeaconRepositoryPort>(
        () => _ProbingBeaconRepository(getIt.get<TenturaDb>()),
      );
    await configureSessionDatabaseTestGraph(env);
    _auth = getIt.get<AuthMiddleware>() as _PausingAuthMiddleware;
    _beacons = getIt.get<BeaconRepositoryPort>() as _ProbingBeaconRepository;
    _bearer = getIt
        .get<AuthCase>()
        .issueAccessToken(cancellationActor)
        .rawToken;

    _workerMessages = ReceivePort();
    final ready = Completer<SendPort>();
    _workerSubscription = _workerMessages.listen((dynamic message) {
      if (message is SendPort && !ready.isCompleted) ready.complete(message);
    });
    // This is the production entry point, including its IO adapter. Starting
    // a separate shelf_io server in the fixture would bypass the wiring under
    // test and could remain green while serveWeb was still uncancellable.
    _worker = serveWeb((sendPort: _workerMessages.sendPort, env: env));
    _stopWorker = await ready.future.timeout(kStableStateWait);

    _directory = await Directory.systemTemp.createTemp('request-cancellation-');
    final config = File('${_directory.path}/Caddyfile');
    await config.writeAsString('''
{
  admin off
  auto_https off
}
http://127.0.0.1:$proxyPort {
  reverse_proxy 127.0.0.1:$upstreamPort
}
''');
    _caddy = await Process.start('caddy', ['run', '--config', config.path]);
    _caddyExit = _caddy.exitCode;
    _caddy.stdout.transform(utf8.decoder).listen(_caddyOutput.write);
    _caddy.stderr.transform(utf8.decoder).listen(_caddyOutput.write);
    origin = Uri.parse('http://127.0.0.1:$proxyPort');
    await _waitForHealth();

    // Verify the fixture and schema before any cancellation assertions.
    final warmup = await create('cancellation-warmup');
    await warmup.done.timeout(kCompletionWait);
    warmup.expectSuccess();
    expect(await rowCount('cancellation-warmup'), 1);
  }

  Future<void> _installSqlBarriers() async {
    await writer.execute('''
      CREATE TABLE public.request_cancellation_probe (
        label text PRIMARY KEY
      )
    ''');
    await writer.execute('''
      CREATE FUNCTION public.cancellation_insert_barrier()
      RETURNS trigger LANGUAGE plpgsql AS \$\$
      BEGIN
        IF NEW.title LIKE 'cancellation-sql-%' THEN
          PERFORM pg_sleep(30);
        ELSIF NEW.title LIKE 'cancellation-lock-%' THEN
          PERFORM pg_advisory_xact_lock($cancellationLockKey::bigint);
        END IF;
        RETURN NEW;
      END;
      \$\$
    ''');
    await writer.execute('''
      CREATE TRIGGER cancellation_insert_barrier
      BEFORE INSERT ON public.beacon FOR EACH ROW
      EXECUTE FUNCTION public.cancellation_insert_barrier()
    ''');
    await writer.execute('''
      CREATE FUNCTION public.cancellation_commit_barrier()
      RETURNS trigger LANGUAGE plpgsql AS \$\$
      BEGIN
        PERFORM pg_advisory_xact_lock($cancellationCommitKey::bigint);
        RETURN NEW;
      END;
      \$\$
    ''');
    await writer.execute('''
      CREATE CONSTRAINT TRIGGER cancellation_commit_barrier
      AFTER INSERT ON public.beacon DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW WHEN (NEW.title LIKE 'cancellation-commit-%')
      EXECUTE FUNCTION public.cancellation_commit_barrier()
    ''');
  }

  AuthenticationPause pauseBeforeAdmission() => _auth.pauseNextRequest();

  /// Runs inside beaconCreate's authenticated production GraphQL resolver.
  /// The callback uses the real scoped database and retry implementations;
  /// it only introduces barriers and records outcomes, never cancellation.
  CancellationRepositoryProbe probeNextCreate(
    Future<void> Function(TenturaDb database) action,
  ) => _beacons.probeNextCreate(action);

  Future<int> probeRowCount(String label) async {
    final rows = await writer.execute(
      Sql.named('''
        SELECT count(*) FROM public.request_cancellation_probe
        WHERE label = @label
      '''),
      parameters: {'label': label},
    );
    return rows.single.single! as int;
  }

  Future<CancellationHttpCall> create(String title, {String? clientOpId}) =>
      graphql(_create, 'CreateWithCancellation', {
        'title': title,
        'clientOpId': clientOpId ?? title,
      });

  Future<CancellationHttpCall> fullSnapshot() => graphql(
    '''
    query ConstellationFieldFetch {
      constellationField(projection: FULL) { loadedAt }
    }''',
    'ConstellationFieldFetch',
    const {},
  );

  Future<CancellationHttpCall> graphql(
    String document,
    String operation,
    Map<String, Object?> variables,
  ) async {
    final client = HttpClient();
    final request = await client.postUrl(origin.resolve('/api/v2/graphql'));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer $_bearer');
    request.add(
      utf8.encode(
        jsonEncode({
          'query': document,
          'operationName': operation,
          'variables': variables,
        }),
      ),
    );
    final call = CancellationHttpCall(client, request);
    _calls.add(call);
    return call;
  }

  Future<int> rowCount(String title) async {
    final rows = await writer.execute(
      Sql.named('SELECT count(*) FROM public.beacon WHERE title = @title'),
      parameters: {'title': title},
    );
    return rows.single.single! as int;
  }

  Future<void> lock(int key) => writer.execute(
    Sql.named('SELECT pg_advisory_lock(@key::bigint)'),
    parameters: {'key': key},
  );

  Future<void> unlock(int key) => writer.execute(
    Sql.named('SELECT pg_advisory_unlock(@key::bigint)'),
    parameters: {'key': key},
  );

  Future<CancellationBackend> waitForBackend(
    bool Function(CancellationBackend) matches,
  ) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < kStableStateWait) {
      final rows = await writer.execute('''
        SELECT pid, query, wait_event
        FROM pg_stat_activity
        WHERE datname = current_database() AND pid <> pg_backend_pid()
          AND state = 'active'
      ''');
      for (final row in rows) {
        final backend = CancellationBackend(
          row[0]! as int,
          row[1]! as String,
          row[2] as String?,
        );
        if (matches(backend)) return backend;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('The production request never reached its held SQL barrier.');
  }

  Future<bool> backendStopped(
    CancellationBackend backend, {
    Duration budget = const Duration(seconds: 2),
  }) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < budget) {
      final active = await writer.execute(
        Sql.named('''
          SELECT 1 FROM pg_stat_activity
          WHERE datname = current_database() AND pid = @pid
            AND state <> 'idle'
        '''),
        parameters: {'pid': backend.pid},
      );
      if (active.isEmpty && pool.admission.running == 0) return true;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return false;
  }

  /// Failure cleanup only; the test records cancellation before invoking it.
  /// No other request is started until this backend has drained. Database and
  /// query predicates prevent touching another suite or a reused connection.
  Future<void> releaseHungBackend(CancellationBackend backend) async {
    await writer.execute(
      Sql.named('''
        SELECT pg_cancel_backend(@pid)
        WHERE EXISTS (
          SELECT 1 FROM pg_stat_activity
          WHERE datname = current_database() AND pid = @pid
            AND state = 'active' AND query = @query
        )
      '''),
      parameters: {'pid': backend.pid, 'query': backend.query},
    );
    expect(
      await backendStopped(backend, budget: kCompletionWait),
      isTrue,
      reason: 'A failing cancellation test must drain its own backend.',
    );
  }

  Future<bool> waitUntil(
    bool Function() predicate, {
    Duration budget = kStableStateWait,
  }) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < budget) {
      if (predicate()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return predicate();
  }

  Future<void> assertUsable(String title) async {
    final call = await create(title);
    await call.done.timeout(kCompletionWait);
    call.expectSuccess();
    expect(await rowCount(title), 1);
    expect(pool.admission.running, 0);
    expect(pool.admission.queued, 0);
  }

  Future<void> _waitForHealth() async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < kStableStateWait) {
      final client = HttpClient();
      try {
        final request = await client.getUrl(origin.resolve('/health'));
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == HttpStatus.ok) return;
      } on SocketException {
        // Caddy and the production worker start independently.
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Caddy did not reach serveWeb: $_caddyOutput');
  }

  Future<void> close() async {
    for (final call in _calls) {
      call.abort();
    }
    await writer.execute('SELECT pg_advisory_unlock_all()');
    _auth.releaseAll();
    // No live request may survive a test failure and block worker shutdown.
    await writer.execute('''
      SELECT pg_cancel_backend(pid) FROM pg_stat_activity
      WHERE datname = current_database() AND pid <> pg_backend_pid()
        AND state = 'active'
    ''');
    _stopWorker.send(null);
    await _worker.timeout(kCompletionWait);
    await _workerSubscription.cancel();
    _workerMessages.close();
    _caddy.kill();
    await _caddyExit.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _caddy.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    await _directory.delete(recursive: true);
    getIt.skipDoubleRegistration = false;
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  }
}

final class CancellationHttpCall {
  CancellationHttpCall(this._client, this._request) {
    // Start sending immediately; tests and cleanup await the captured future.
    done = _receiveResponse();
  }

  final HttpClient _client;
  final HttpClientRequest _request;
  late final Future<void> done;
  int? statusCode;
  Map<String, dynamic>? payload;
  Object? transportError;

  Future<void> _receiveResponse() async {
    try {
      final response = await _request.close();
      statusCode = response.statusCode;
      payload =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
    } on Object catch (error) {
      transportError = error;
    }
  }

  void abort() {
    _request.abort(const HttpException('Caller abandoned request'));
    // Each call owns its HttpClient. Force-closing it tears down the socket
    // to Caddy even after request.close() has started waiting for a response.
    _client.close(force: true);
  }

  Future<void> abortInFlight() async {
    expect(
      statusCode,
      isNull,
      reason: 'The request must still be waiting for Caddy before aborting.',
    );
    expect(payload, isNull);
    abort();
    await done.timeout(kCompletionWait);
    expect(
      transportError,
      anyOf(isA<HttpException>(), isA<SocketException>()),
      reason:
          'Aborting must fail the in-flight transport to Caddy. Backend '
          'cancellation is asserted separately while its barrier is held.',
    );
    expect(statusCode, isNull);
    expect(payload, isNull);
  }

  void expectSuccess() {
    expect(transportError, isNull);
    expect(statusCode, HttpStatus.ok);
    expect(payload, isNotNull);
    expect(payload!['errors'], isNull, reason: '${payload!}');
    expect(payload!['data'], isNotNull);
  }
}

final class CancellationBackend {
  const CancellationBackend(this.pid, this.query, this.waitEvent);

  final int pid;
  final String query;
  final String? waitEvent;
}

final class CancellationRepositoryProbe {
  CancellationRepositoryProbe(this.action);

  final Future<void> Function(TenturaDb database) action;
  final finished = Completer<void>();
  Object? error;
}

/// Keep the production resolver, use case and repository in the call graph.
/// Only the rate-limit lookup is augmented with the next test's DB callback.
final class _ProbingBeaconRepository extends BeaconRepository {
  _ProbingBeaconRepository(this.database) : super(database);

  final TenturaDb database;
  CancellationRepositoryProbe? _next;

  CancellationRepositoryProbe probeNextCreate(
    Future<void> Function(TenturaDb database) action,
  ) {
    if (_next != null) throw StateError('A repository probe is already armed');
    return _next = CancellationRepositoryProbe(action);
  }

  @override
  Future<int> countRecentByAuthor({
    required String userId,
    required Duration window,
  }) async {
    final probe = _next;
    _next = null;
    if (probe != null) {
      try {
        await probe.action(database);
      } on Object catch (error) {
        probe.error = error;
        rethrow;
      } finally {
        probe.finished.complete();
      }
    }
    return super.countRecentByAuthor(userId: userId, window: window);
  }
}

final class AuthenticationPause {
  final entered = Completer<void>();
  final release = Completer<void>();
  final finished = Completer<void>();
}

final class _PausingAuthMiddleware extends AuthMiddleware {
  _PausingAuthMiddleware(super._authCase, super._sessionCase);

  final _pauses = <AuthenticationPause>[];
  AuthenticationPause? _next;

  AuthenticationPause pauseNextRequest() {
    final pause = AuthenticationPause();
    _pauses.add(pause);
    _next = pause;
    return pause;
  }

  void releaseAll() {
    for (final pause in _pauses) {
      if (!pause.release.isCompleted) pause.release.complete();
    }
  }

  @override
  Middleware get extractJwtClaims => (handler) {
    final delegate = super.extractJwtClaims(handler);
    return (request) async {
      final pause = _next;
      _next = null;
      if (pause == null) return delegate(request);
      pause.entered.complete();
      try {
        await pause.release.future;
        return await delegate(request);
      } finally {
        pause.finished.complete();
      }
    };
  };
}

Future<int> _unusedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
