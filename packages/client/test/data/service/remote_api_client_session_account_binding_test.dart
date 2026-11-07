// #1044: on web every request uses a token minted from one HttpOnly session
// cookie shared by all tabs, so the UI account can differ from the token's
// user. A refreshed token whose user id does not match the bound account must
// be discarded before any request carries it, and the client must raise a
// "session account changed" error instead of leaking the other user's token.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:tentura/features/my_work/data/repository/my_work_repository.dart';

import '../../support/graphql_round_trip_server.dart';
import '_session_account_test_harness.dart';

const _accountA = 'account-a';
const _accountB = 'account-b';
const _tokenA = 'token-account-a';
const _tokenB = 'token-account-b';

Uri get _jsonUri => Uri.parse('https://example.test/api/v2/probe');

void main() {
  group('session token bound to the signed-in account', () {
    test(
      'a repository GraphQL read rejects a swapped-cookie account before '
      'sending its bearer token',
      () async {
        final cookie = FakeSessionCookie(subject: _accountA, token: _tokenA);
        final requests = <http.Request>[];
        final graphql = GraphqlRoundTripServer(
          viewerId: _accountA,
          overrides: (parent, field, operation) {
            if (operation == 'MyWorkInit' && field == 'beacon_archived') {
              return GraphqlRoundTripServer.oneRow;
            }
            return GraphqlRoundTripServer.auto;
          },
        );
        final graphqlClient = graphql.client;
        addTearDown(graphqlClient.close);
        final server = fakeSessionServer(
          cookie,
          seen: requests,
          graphQlServer: graphqlClient,
        );

        await http.runWithClient(() async {
          final client = testRealtimeClient();
          addTearDown(client.close);
          await client.setSessionAuth();
          await client.bindRealtimeAccount(_accountA);
          final repository = MyWorkRepository(client);

          // A real response goes through HTTP, Ferry and the repository mapper.
          // The nonzero count makes a no-op/empty repository fail this control.
          final firstRead = repository.fetchInit(userId: _accountA);
          await Future.wait([firstRead, graphql.drain()]);
          expect((await firstRead).archivedCountHint, 1);
          expect(
            requests
                .where((r) => r.url.path.endsWith('/graphql'))
                .single
                .headers,
            containsPair('Authorization', 'Bearer $_tokenA'),
          );

          cookie
            ..subject = _accountB
            ..token = _tokenB;
          requests.clear();
          // Observe both success and failure so the fake server can drain
          // without leaving an unhandled assertion/future error behind.
          final secondRead = repository
              .fetchInit(userId: _accountA)
              .then<Object>(
                (value) => value,
                onError: (Object error) => error,
              );
          await Future.wait([secondRead, graphql.drain()]);

          expect(
            requests.where((r) => r.url.path == '/api/v2/session/access-token'),
            isNotEmpty,
          );
          expect(
            requests.map((request) => request.headers['Authorization']),
            isNot(contains('Bearer $_tokenB')),
            reason: 'the server must never receive the other account bearer',
          );
          expect(
            requests.where((r) => r.url.path.endsWith('/graphql')),
            isEmpty,
            reason: 'the client must abort the read before sending token-b',
          );
          expect(await secondRead, isSessionAccountChangedNotice);
          expect(client.realtimeAccountId, _accountA);
        }, () => server);
      },
    );

    test(
      'a refreshed token minted for a different account is rejected and never '
      'sent to the server on any request',
      () async {
        final cookie = FakeSessionCookie(
          subject: _accountA,
          token: _tokenA,
        );
        final seenRequests = <http.Request>[];
        final fakeServer = fakeSessionServer(cookie, seen: seenRequests);

        await http.runWithClient(() async {
          final client = testRealtimeClient();
          addTearDown(client.close);
          await client.setSessionAuth();
          await client.bindRealtimeAccount(_accountA);

          // First refresh mints token-a for the bound account; an
          // authenticated request carries it.
          final first = await client.getAuthToken();
          expect(first.accessToken, _tokenA);
          expect(first.userId, _accountA);
          await client.getAuthenticatedJson(_jsonUri);
          expect(
            seenRequests.where((r) => r.url == _jsonUri).last.headers,
            containsPair('Authorization', 'Bearer $_tokenA'),
          );

          // Another tab signs in as account-b: the shared cookie now mints
          // account-b's token.
          cookie
            ..subject = _accountB
            ..token = _tokenB;
          seenRequests.clear();

          // The client must reject the mismatched token before any request
          // uses it, raising the new "session account changed" error.
          await expectLater(
            client.getAuthToken(),
            throwsA(isSessionAccountChangedNotice),
          );
          // An authenticated call must not leak the other user's token: it
          // surfaces the rejection instead of sending Bearer token-b.
          await expectLater(
            client.getAuthenticatedJson(_jsonUri),
            throwsA(isSessionAccountChangedNotice),
          );

          // The server never received account-b's token on any request,
          // through any channel: header, body, or URL.
          for (final r in seenRequests) {
            expect(
              r.headers['Authorization'],
              isNot('Bearer $_tokenB'),
              reason: 'token-b leaked via Authorization header on ${r.url}',
            );
            expect(
              r.url.toString(),
              isNot(contains(_tokenB)),
              reason: 'token-b leaked via URL on $r',
            );
            if (r.body case final body when body.isNotEmpty) {
              expect(
                body,
                isNot(contains(_tokenB)),
                reason: 'token-b leaked via request body on ${r.url}',
              );
              // A JSON body might also carry the subject; guard it too.
              if (body.startsWith('{')) {
                expect(
                  jsonDecode(body),
                  isNot(containsPair('subject', _accountB)),
                );
              }
            }
          }

          // The mismatched token was discarded, not cached: once the cookie
          // mints account-a again, an authenticated request carries token-a.
          cookie
            ..subject = _accountA
            ..token = _tokenA;
          seenRequests.clear();
          final restored = await client.getAuthToken();
          expect(restored.accessToken, _tokenA);
          expect(restored.userId, _accountA);
          await client.getAuthenticatedJson(_jsonUri);
          expect(
            seenRequests.where((r) => r.url == _jsonUri).last.headers,
            containsPair('Authorization', 'Bearer $_tokenA'),
          );
        }, () => fakeServer);
      },
    );
  });
}
