import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/my_work/data/gql/_g/my_work_fetch.req.gql.dart';

import '../../support/remote_load_failure_matcher.dart';

void main() {
  test(
    'closing a queued Home desk request reports a remote failure without No element',
    () async {
      final neverAnswers = Completer<http.Response>();
      final server = MockClient((request) async {
        if (request.url.path.endsWith('/session/access-token')) {
          return http.Response(
            jsonEncode({
              'subject': 'Uauthor000001',
              'access_token': 'test-token',
              'expires_in': 3600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return neverAnswers.future;
      });
      await http.runWithClient(() async {
        final remote = RemoteApiService(
          const Env(),
          const WebSocketClientRealtimeSocketFactory(),
        );
        try {
          await remote.setSessionAuth();
          final pending = remote
              .request(GMyWorkInitReq((b) => b..vars.userId = 'Uauthor000001'))
              .firstWhere((event) => event.dataSource == DataSource.Link);
          final outcome = expectLater(pending, throwsA(remoteLoadFailure()));
          await remote.close();
          await outcome.timeout(const Duration(seconds: 5));
        } finally {
          await remote.close();
        }
      }, () => server);
    },
  );

  group(
    'RemoteApiService request stream when the service is closed mid-flight',
    () {
      test(
        'closing the service fails an in-flight request with a typed exception',
        () async {
          final neverAnswers = Completer<http.Response>();
          final server = MockClient((request) async {
            if (request.url.path.endsWith('/session/access-token')) {
              return http.Response(
                jsonEncode({
                  'subject': 'Uauthor000001',
                  'access_token': 'test-token',
                  'expires_in': 3600,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return neverAnswers.future;
          });

          await http.runWithClient(() async {
            final remote = RemoteApiService(
              const Env(),
              const WebSocketClientRealtimeSocketFactory(),
            );
            await remote.setSessionAuth();

            final pending = remote
                .request(
                  GMyWorkInitReq((b) => b..vars.userId = 'Uauthor000001'),
                )
                .firstWhere((e) => e.dataSource == DataSource.Link);
            // An empty firstWhere currently produces StateError('No element').
            // Require a recognised remote failure rather than any Exception.
            final outcome = expectLater(pending, throwsA(remoteLoadFailure()));

            await Future<void>.delayed(const Duration(milliseconds: 100));
            await remote.close();
            await outcome.timeout(const Duration(seconds: 5));
          }, () => server);
        },
      );
    },
  );
}
