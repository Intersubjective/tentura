// #1044: the realtime socket re-auth must not send another account's token.
// On web the shared HttpOnly cookie can be swapped to a different user by
// another tab; when the socket (re)connects and re-authenticates, the refreshed
// token whose user id does not match the bound account must be discarded
// before it is sent on the wire, and the reconnect's re-auth must raise the
// "session account changed" error.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:tentura/data/service/remote_api_client/realtime_socket.dart';
import 'package:tentura/data/service/remote_api_client/realtime_transport_status.dart';

import '_session_account_test_harness.dart';

const _accountA = 'account-a';
const _accountB = 'account-b';
const _tokenA = 'token-account-a';
const _tokenB = 'token-account-b';

void _acceptAuthentication(FakeRealtimeSocket socket) {
  socket.addMessage(
    jsonEncode({'type': 'auth', 'intent': 'sign_in', 'result': 'success'}),
  );
}

Future<void> _settle([
  Duration delay = const Duration(milliseconds: 20),
]) => Future<void>.delayed(delay);

void main() {
  group('realtime socket re-auth bound to the signed-in account', () {
    test(
      'a reconnect re-auth raises the session account changed error and '
      'never sends the other account token on any socket',
      () async {
        final cookie = FakeSessionCookie(subject: _accountA, token: _tokenA);
        final fakeServer = fakeSessionServer(cookie);

        await http.runWithClient(() async {
          final factory = FakeRealtimeSocketFactory();
          final client = testRealtimeClient(socketFactory: factory);
          addTearDown(client.close);
          await client.setSessionAuth();
          await client.bindRealtimeAccount(_accountA);

          // Track every reconnect re-auth attempt via the transport stream.
          final phases = <RealtimeTransportPhase>[];
          final statusSub = client.realtimeTransportStatus.listen(
            (s) => phases.add(s.phase),
          );
          addTearDown(statusSub.cancel);

          final initialSocket = factory.sockets.single
            ..addConnection(RealtimeSocketConnectionState.connected);
          // Bounded wait for the initial auth frame (fail, not hang, if none).
          await waitUntil(
            'initial auth frame was never sent',
            () => initialSocket.sent.isNotEmpty,
          );
          expect(
            jsonDecode(initialSocket.sent.single as String),
            containsPair('token', _tokenA),
          );
          _acceptAuthentication(initialSocket);
          await _settle();

          // Another tab signs in as account-b: the shared cookie now mints
          // account-b's token.
          cookie
            ..subject = _accountB
            ..token = _tokenB;
          for (final s in factory.sockets) {
            s.sent.clear();
          }
          phases.clear();

          // A network reconnect forces the socket to re-authenticate.
          initialSocket
            ..addConnection(RealtimeSocketConnectionState.disconnected)
            ..addConnection(RealtimeSocketConnectionState.reconnected);
          // Give the re-auth/retry loop time to attempt sending a frame.
          await _settle(const Duration(milliseconds: 300));

          // Positive: a re-auth was attempted on the reconnect (the transport
          // entered the authenticating phase), so the "never sends token-b"
          // check below is not vacuous.
          expect(
            phases,
            contains(RealtimeTransportPhase.authenticating),
            reason: 'reconnect did not attempt re-auth',
          );

          // No socket — the initial one or any opened on reconnect — ever sent
          // account-b's token on the wire.
          for (final s in factory.sockets) {
            for (final frame in s.sent) {
              if (frame is String) {
                expect(
                  frame,
                  isNot(contains(_tokenB)),
                  reason: 'token-b sent on a realtime socket',
                );
              }
            }
          }

          // The bound account is still account-a; the swapped cookie now
          // mints account-b. The reconnect's re-auth calls getAuthToken, which
          // must raise the new "session account changed" error rather than
          // hand the other user's token to a caller.
          expect(client.realtimeAccountId, _accountA);
          await expectLater(
            client.getAuthToken(),
            throwsA(isSessionAccountChangedNotice),
          );
        }, () => fakeServer);
      },
    );
  });
}
