import 'dart:async';

import 'package:ferry/ferry.dart' as gql show ServerException;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show GraphQLError, Response;
import 'package:tentura/data/service/remote_api_client/auth_loss_classifier.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';

Future<ParallelWaitError<Object?, Object?>> _parallelFailure(
  List<Future<Object?>> futures,
) async {
  try {
    await futures.wait;
    // ParallelWaitError is the failure shape under test.
    // ignore: avoid_catching_errors
  } on ParallelWaitError<Object?, Object?> catch (error) {
    return error;
  }
  fail('expected the parallel wait to fail');
}

const _busyError = {
  'message': 'Constellation database busy, retry later',
  'extensions': {'code': '1704', 'retryAfterMs': 250},
};

GraphQLError _busy() => GraphQLError(
  message: _busyError['message']! as String,
  extensions: Map<String, dynamic>.of(
    _busyError['extensions']! as Map<String, dynamic>,
  ),
);

void _expectRetryLater(Object? mapped, {Duration? retryAfter}) {
  expect(mapped, isA<RemoteApiRetryLaterException>());
  if (retryAfter != null) {
    expect((mapped! as RemoteApiRetryLaterException).retryAfter, retryAfter);
  }
}

void main() {
  group('server admission backoff on the wire', () {
    test('GraphQL errors carrying numeric-string code 1704 and retryAfterMs '
        'map to retry-later', () {
      _expectRetryLater(
        mapRemoteFailure(<GraphQLError>[_busy()]),
        retryAfter: const Duration(milliseconds: 250),
      );
    });

    test('a link server exception wrapping code 1704 maps to retry-later', () {
      _expectRetryLater(
        mapRemoteFailure(
          gql.ServerException(
            statusCode: 200,
            parsedResponse: Response(
              errors: [_busy()],
              response: const {},
            ),
          ),
        ),
        retryAfter: const Duration(milliseconds: 250),
      );
    });
  });

  group('parallel wait failures', () {
    test('only retry-later causes are classified as retry-later', () async {
      final failure = await _parallelFailure([
        Future<Object?>.error(
          const RemoteApiRetryLaterException(Duration(milliseconds: 200)),
        ),
        Future<Object?>.error(
          const RemoteApiRetryLaterException(Duration(milliseconds: 900)),
        ),
      ]);

      _expectRetryLater(mapRemoteFailure(failure));
    });

    test('a succeeded sibling does not hide the retry-later cause', () async {
      final failure = await _parallelFailure([
        Future<Object?>.value('ok'),
        Future<Object?>.error(
          const RemoteApiRetryLaterException(Duration(milliseconds: 300)),
        ),
      ]);

      expect(mapRemoteFailure(failure), isA<RemoteApiRetryLaterException>());
    });

    // Deliberate policy, not an acceptance requirement: retrying cannot
    // recover a lost session, so it must win over a retry-later sibling.
    test('a session loss among the causes wins over a retry-later sibling, '
        'because retrying cannot recover a lost session', () async {
      final failure = await _parallelFailure([
        Future<Object?>.error(
          const RemoteApiRetryLaterException(Duration(milliseconds: 300)),
        ),
        Future<Object?>.error(const AuthSessionLostException()),
      ]);

      expect(mapRemoteFailure(failure), isA<AuthSessionLostException>());
    });
  });
}
