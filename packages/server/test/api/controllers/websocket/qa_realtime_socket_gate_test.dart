import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/websocket/session/qa_realtime_socket_gate.dart';

void main() {
  test('suspend closes every isolate-local session and blocks auth', () async {
    final gate = QaRealtimeSocketGate();
    final closed = <Object>[];
    final first = Object();
    final second = Object();
    gate
      ..registerBootstrappedUser('helper')
      ..registerSession(
        userId: 'helper',
        session: first,
        close: () async => closed.add(first),
      )
      ..registerSession(
        userId: 'helper',
        session: second,
        close: () async => closed.add(second),
      );

    final count = await gate.suspendAndClose('helper');

    expect(count, 2);
    expect(closed, unorderedEquals([first, second]));
    expect(gate.isAuthenticationSuspended('helper'), isTrue);
    expect(gate.wasBootstrapped('helper'), isTrue);
  });

  test(
    'resume re-enables auth and unregister removes the close hook',
    () async {
      final gate = QaRealtimeSocketGate();
      final session = Object();
      var closeCount = 0;
      gate
        ..registerSession(
          userId: 'helper',
          session: session,
          close: () async {
            closeCount++;
          },
        )
        ..unregisterSession(session);

      expect(await gate.suspendAndClose('helper'), 0);
      gate.resume('helper');

      expect(closeCount, 0);
      expect(gate.isAuthenticationSuspended('helper'), isFalse);
    },
  );
}
