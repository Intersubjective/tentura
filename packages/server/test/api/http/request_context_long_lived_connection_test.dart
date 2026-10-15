import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/http/request_context_io_adapter.dart';
// Drift re-exports isNull/isNotNull, which clash with package:test matchers.
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/user_presence_repository.dart';
import 'package:tentura_server/domain/request_context.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/transaction_statement_recorder.dart';

// The default request budget is 5 s (see RequestContext). Callbacks wait 6 s
// so they run strictly after it has expired even on a slow machine; do not
// shorten this below the budget plus a safety margin.
const _pastBudget = Duration(seconds: 6);

void main() {
  group('requestContextIoAdapter long-lived connections', () {
    late HttpServer server;
    late TransactionStatementRecorder recorder;
    late UserPresenceCase presence;
    late List<Object> uncaught;
    late Completer<Object?> closeOutcome;
    late Completer<Object?> messageOutcome;
    late Completer<Object?> slowHttpOutcome;

    bool wrotePresence(UserPresenceStatus status) => recorder.statements.any(
      (s) =>
          s.sql.toUpperCase().contains('UPDATE') &&
          s.sql.contains('user_presence') &&
          s.arguments.any((a) => a == status.index),
    );

    setUp(() async {
      uncaught = [];
      closeOutcome = Completer<Object?>();
      messageOutcome = Completer<Object?>();
      slowHttpOutcome = Completer<Object?>();
      recorder = TransactionStatementRecorder(select: (sql, args) => []);
      final database = TenturaDb.forTest(database: recorder);
      addTearDown(database.close);
      presence = UserPresenceCase(
        UserPresenceRepository(database),
        env: Env(environment: Environment.test, printEnv: false),
        logger: Logger('RequestContextLongLivedConnectionTest'),
      );

      // Everything the server schedules runs in this guarded zone, so a fatal
      // error escaping a socket callback lands in [uncaught].
      final started = Completer<HttpServer>();
      unawaited(
        runZonedGuarded(
          () async {
            final app = Router().plus
              ..get(
                '/$kPathWebSocketEndpoint',
                () => WebSocketSession(
                  onMessage: (session, data) async {
                    await Future<void>.delayed(_pastBudget);
                    try {
                      await database.withConnectionScope(
                        () => presence.setStatus(
                          userId: 'user-1',
                          status: UserPresenceStatus.online,
                        ),
                      );
                      messageOutcome.complete(null);
                    } on Object catch (error) {
                      messageOutcome.complete(error);
                    }
                  },
                  onClose: (session) async {
                    try {
                      await database.withConnectionScope(
                        () => presence.setStatus(
                          userId: 'user-1',
                          status: UserPresenceStatus.offline,
                        ),
                      );
                      closeOutcome.complete(null);
                    } on Object catch (error) {
                      closeOutcome.complete(error);
                    }
                  },
                ),
              )
              ..get('/plain', () => 'ok')
              ..get('/slow', () async {
                await Future<void>.delayed(_pastBudget);
                try {
                  RequestContext.current?.check();
                  slowHttpOutcome.complete(null);
                } on Object catch (error) {
                  slowHttpOutcome.complete(error);
                }
                return 'late';
              });
            started.complete(
              await shelf_io.serve(
                requestContextIoAdapter(app.call),
                InternetAddress.loopbackIPv4,
                0,
              ),
            );
          },
          (error, _) => uncaught.add(error),
        ),
      );
      server = await started.future;
    });

    tearDown(() => server.close(force: true));

    String wsUrl() => 'ws://${server.address.host}:${server.port}/$kPathWebSocketEndpoint';

    test(
      'a socket close callback past the request budget writes offline presence '
      'without a deadline error',
      () async {
        final socket = await WebSocket.connect(wsUrl());
        await Future<void>.delayed(_pastBudget);
        await socket.close();
        final outcome = await closeOutcome.future.timeout(
          const Duration(seconds: 5),
        );
        expect(outcome, isNull, reason: 'close callback must not throw');
        expect(
          wrotePresence(UserPresenceStatus.offline),
          isTrue,
          reason: 'offline presence not written',
        );
        expect(uncaught, isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'a socket message callback past the request budget writes online '
      'presence',
      () async {
        final socket = await WebSocket.connect(wsUrl());
        socket.add('ping');
        final outcome = await messageOutcome.future.timeout(
          const Duration(seconds: 10),
        );
        expect(outcome, isNull, reason: 'message callback must not throw');
        expect(
          wrotePresence(UserPresenceStatus.online),
          isTrue,
          reason: 'online presence not written',
        );
        await socket.close();
        expect(uncaught, isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      // Cancellation on the graphql hijack branch is covered by the existing
      // request-context adapter tests; this only guards the plain deadline.
      'an ordinary HTTP request keeps its deadline past the request budget',
      () async {
        final client = HttpClient();
        addTearDown(client.close);
        final request = await client.getUrl(
          Uri.parse('http://${server.address.host}:${server.port}/slow'),
        );
        await (await request.close()).drain<void>();
        expect(await slowHttpOutcome.future, isA<TimeoutException>());
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
