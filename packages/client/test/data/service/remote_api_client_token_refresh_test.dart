import 'dart:async';
import 'dart:convert';

import 'package:ferry/ferry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_client/remote_api_client_base.dart';

void main() {
  group('RemoteApiClientBase.getAuthToken', () {
    test(
      'concurrent callers share one slow session refresh instead of timing out',
      () async {
        var accessTokenCalls = 0;
        final slowServer = MockClient((request) async {
          accessTokenCalls++;
          // Longer than the old 1.5s lock poll that failed waiters.
          await Future<void>.delayed(const Duration(seconds: 2));
          return http.Response(
            jsonEncode({
              'subject': 'account-a',
              'access_token': 'token-a',
              'expires_in': 300,
            }),
            200,
          );
        });

        await http.runWithClient(() async {
          final client = _TestClient();
          await client.setSessionAuth();

          final results = await Future.wait([
            client.getAuthToken(),
            client.getAuthToken(),
            client.getAuthToken(),
          ]);

          expect(results.map((c) => c.accessToken), everyElement('token-a'));
          expect(accessTokenCalls, 1);
        }, () => slowServer);
      },
    );

    test('a failed refresh is not cached; the next call retries', () async {
      var accessTokenCalls = 0;
      final flakyServer = MockClient((request) async {
        accessTokenCalls++;
        if (accessTokenCalls == 1) {
          return http.Response('upstream timeout', 504);
        }
        return http.Response(
          jsonEncode({
            'subject': 'account-a',
            'access_token': 'token-a',
            'expires_in': 300,
          }),
          200,
        );
      });

      await http.runWithClient(() async {
        final client = _TestClient();
        await client.setSessionAuth();

        await expectLater(client.getAuthToken(), throwsA(anything));
        final credentials = await client.getAuthToken();

        expect(credentials.accessToken, 'token-a');
        expect(accessTokenCalls, 2);
      }, () => flakyServer);
    });
  });
}

final class _TestClient extends RemoteApiClientBase {
  _TestClient()
    : super(
        userAgent: 'test',
        apiEndpointUrl: 'https://example.test/api/v1/graphql',
        apiEndpointUrlV2: 'https://example.test/api/v2/graphql',
        requestTimeout: const Duration(seconds: 10),
        authJwtExpiresIn: const Duration(minutes: 1),
      );

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) => const Stream.empty();
}
