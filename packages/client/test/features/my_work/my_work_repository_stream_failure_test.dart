// Repository regressions for the Ferry link chain used by the Home desk.
// HomeRoute presentation and the attention prerequisite are exercised in
// home_my_work_load_failure_test.dart; these tests isolate the transport.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/my_work/data/repository/my_work_repository.dart';

import '../../support/remote_load_failure_matcher.dart';

http.Response _token() => http.Response(
  jsonEncode({
    'subject': 'Uauthor000001',
    'access_token': 'test-token',
    'expires_in': 3600,
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// Runs [body] against a real [RemoteApiService] whose GraphQL transport is
/// [graphql]; the session-token endpoint always succeeds.
Future<void> _withRemote(
  Future<http.Response> Function(http.Request request) graphql,
  Future<void> Function(RemoteApiService remote, MyWorkRepository repo) body,
) => http.runWithClient(
  () async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    try {
      await remote.setSessionAuth();
      await body(remote, MyWorkRepository(remote));
    } finally {
      await remote.close();
    }
  },
  () => MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) return _token();
    return graphql(request);
  }),
);

void main() {
  group('MyWorkRepository.fetchInit when the transport fails', () {
    test('a service closed mid-flight fails with a typed exception', () async {
      final neverAnswers = Completer<http.Response>();
      await _withRemote((_) => neverAnswers.future, (remote, repo) async {
        final pending = repo.fetchInit(userId: 'Uauthor000001');
        final outcome = expectLater(pending, throwsA(remoteLoadFailure()));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await remote.close();
        await outcome.timeout(const Duration(seconds: 5));
      });
    });

    test('a service closed mid-flight fails the last-activity lookup with a '
        'typed exception', () async {
      final neverAnswers = Completer<http.Response>();
      await _withRemote((_) => neverAnswers.future, (remote, repo) async {
        final pending = repo.fetchLastActivityEventsByBeaconId([
          'Bbeacon00001',
        ]);
        final outcome = expectLater(pending, throwsA(remoteLoadFailure()));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await remote.close();
        await outcome.timeout(const Duration(seconds: 5));
      });
    });

    test('a 500 response fails with a typed exception', () async {
      await _withRemote(
        (_) async => http.Response('boom', 500),
        (_, repo) => expectLater(
          repo.fetchInit(userId: 'Uauthor000001'),
          throwsA(remoteLoadFailure()),
        ),
      );
    });

    test('a 401 response fails with a typed exception', () async {
      await _withRemote(
        (_) async => http.Response('unauthorized', 401),
        (_, repo) => expectLater(
          repo.fetchInit(userId: 'Uauthor000001'),
          throwsA(remoteLoadFailure()),
        ),
      );
    });

    test('a GraphQL error payload fails with a typed exception', () async {
      await _withRemote(
        (_) async => http.Response(
          jsonEncode({
            'data': null,
            'errors': [
              {'message': 'attention unavailable'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
        (_, repo) => expectLater(
          repo.fetchInit(userId: 'Uauthor000001'),
          throwsA(remoteLoadFailure()),
        ),
      );
    });
  });

  group('MyWorkRepository.fetchArchived when transport fails', () {
    test(
      'closing a queued archive request reports a remote failure without No element',
      () async {
        final neverAnswers = Completer<http.Response>();
        await _withRemote((_) => neverAnswers.future, (remote, repo) async {
          final pending = repo.fetchArchived(userId: 'Uauthor000001');
          final outcome = expectLater(pending, throwsA(remoteLoadFailure()));
          await remote.close();
          await outcome.timeout(const Duration(seconds: 5));
        });
      },
    );

    test(
      'a service closed mid-flight reports a recoverable remote failure',
      () async {
        final neverAnswers = Completer<http.Response>();
        await _withRemote((_) => neverAnswers.future, (remote, repo) async {
          final pending = repo.fetchArchived(userId: 'Uauthor000001');
          final outcome = expectLater(pending, throwsA(remoteLoadFailure()));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await remote.close();
          await outcome.timeout(const Duration(seconds: 5));
        });
      },
    );

    test('an HTTP failure reports a recoverable remote failure', () async {
      await _withRemote(
        (_) async => http.Response('boom', 500),
        (_, repo) => expectLater(
          repo.fetchArchived(userId: 'Uauthor000001'),
          throwsA(remoteLoadFailure()),
        ),
      );
    });
  });
}
