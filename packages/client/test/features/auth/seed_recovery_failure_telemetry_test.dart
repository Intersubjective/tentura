import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tentura/data/service/remote_api_client/auth_box.dart';
import 'package:tentura/data/service/remote_api_client/auth_remote_client.dart';
import 'package:tentura/data/service/remote_api_client/credentials.dart';
import 'package:tentura/data/service/remote_api_client/session_fetch.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/data/repository/auth_remote_repository.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import 'auth_test_helpers.dart' show EmptyAuthLocal;

void main() {
  group('Seed recovery reports each remote failure once', () {
    const authAttemptId = 'seed-recovery-attempt-1234';
    final seed = base64UrlEncode(List<int>.filled(kSeedLength, 1));
    late _RecordingTelemetry telemetry;
    late _FailingAuthRemoteClient client;
    late _RecordingAuthLocal local;
    late _RecordingProfileRepository profiles;
    late AccountCase accountCase;

    setUp(() async {
      telemetry = _RecordingTelemetry();
      await Sentry.init((options) {
        options
          ..dsn = 'https://public@example.invalid/1'
          ..debug = false
          ..enableDeduplication = false
          ..sendClientReports = false
          ..transport = telemetry;
        // Capture SDK events without sending telemetry or installing global
        // error handlers that could report unrelated test-runner failures.
        options.integrations.toList().forEach(options.removeIntegration);
        options.beforeSend = (event, hint) {
          telemetry.events.add(event);
          return null;
        };
      });
      client = _FailingAuthRemoteClient();
      local = _RecordingAuthLocal();
      profiles = _RecordingProfileRepository();
      accountCase = AccountCase(
        local,
        AuthRemoteRepository(
          remoteApiService: client,
          log: Logger('seed-recovery-remote-test'),
        ),
        _UnusedPlatformRepository(),
        profiles,
        env: const Env(),
        logger: Logger('seed-recovery-test'),
      );
    });

    tearDown(() async {
      await Sentry.close();
    });

    void expectSingleCapture(String outcome, [Object? error]) {
      expect(
        telemetry.events.map((event) => event.tags?['auth_outcome']).toList(),
        [outcome],
        reason: 'A failed seed recovery must emit exactly one exception event.',
      );
      final event = telemetry.events.single;
      if (error != null) {
        expect(event.throwable, same(error));
      }
      expect(event.tags?['auth_method'], 'seed');
      expect(event.tags?['auth_attempt_id'], authAttemptId);
      expect(profiles.fetchCalls, 0);
      expect(local.writes, isEmpty);
      expect(client.boundAccountIds, isEmpty);
      expect(telemetry.sentEnvelopes, isEmpty);
    }

    for (final statusCode in [408, 429, 503]) {
      test(
        'from-bearer HTTP $statusCode captures only session_cookie_failed',
        () async {
          final failure = SessionHttpException(statusCode);
          client.sessionError = failure;

          await expectLater(
            accountCase.recoverFromSeedAndSignIn(
              seed,
              authAttemptId: authAttemptId,
            ),
            throwsA(isA<AuthServerUnavailableException>()),
          );

          expect(client.sessionAttemptIds, [authAttemptId]);
          expect(client.tokenCalls, 1);
          expect(client.receivedSeed, seed);
          expectSingleCapture('session_cookie_failed', failure);
        },
      );
    }

    for (final failure in [
      SessionHttpException(503),
      TimeoutException('auth token request timed out'),
    ]) {
      test(
        'transient token fetch ${failure.runtimeType} captures remote_sign_in_failed once',
        () async {
          client.tokenError = failure;

          await expectLater(
            accountCase.recoverFromSeedAndSignIn(
              seed,
              authAttemptId: authAttemptId,
            ),
            throwsA(isA<AuthServerUnavailableException>()),
          );

          expect(client.tokenCalls, 1);
          expect(client.sessionAttemptIds, isEmpty);
          expectSingleCapture('remote_sign_in_failed');
        },
      );
    }

    test(
      'non-transient token failure captures remote_sign_in_failed once',
      () async {
        final failure = StateError('invalid token response');
        client.tokenError = failure;

        await expectLater(
          accountCase.recoverFromSeedAndSignIn(
            seed,
            authAttemptId: authAttemptId,
          ),
          throwsA(same(failure)),
        );

        expect(client.sessionAttemptIds, isEmpty);
        expectSingleCapture('remote_sign_in_failed', failure);
      },
    );

    test(
      'non-transient from-bearer failure captures session_cookie_failed once',
      () async {
        final failure = SessionHttpException(400);
        client.sessionError = failure;

        await expectLater(
          accountCase.recoverFromSeedAndSignIn(
            seed,
            authAttemptId: authAttemptId,
          ),
          throwsA(same(failure)),
        );

        expect(client.sessionAttemptIds, [authAttemptId]);
        expectSingleCapture('session_cookie_failed', failure);
      },
    );
  });
}

class _RecordingTelemetry implements Transport {
  final events = <SentryEvent>[];
  final sentEnvelopes = <SentryEnvelope>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    sentEnvelopes.add(envelope);
    return null;
  }
}

class _FailingAuthRemoteClient implements AuthRemoteClient {
  Object? tokenError;
  Object? sessionError;
  String? receivedSeed;
  int tokenCalls = 0;
  final sessionAttemptIds = <String?>[];
  final boundAccountIds = <String>[];

  @override
  Future<void> dropAuth() async {}

  @override
  Future<String?> setAuth({
    required String seed,
    required AuthTokenFetcher authTokenFetcher,
    AuthRequestIntent? returnAuthRequestToken,
  }) async {
    receivedSeed = seed;
    return null;
  }

  @override
  Future<Credentials> getAuthToken() async {
    tokenCalls++;
    final error = tokenError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    return Credentials(
      userId: 'seed-account',
      accessToken: 'access-token',
      expiresAt: DateTime.timestamp().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<void> establishSessionFromBearer({String? authAttemptId}) async {
    sessionAttemptIds.add(authAttemptId);
    final error = sessionError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
  }

  @override
  Future<void> bindRealtimeAccount(String accountId) async {
    boundAccountIds.add(accountId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingAuthLocal extends EmptyAuthLocal {
  final writes = <String>[];

  @override
  Future<void> upsertAccountWithSeed(
    String id,
    String seed, [
    String? displayName,
  ]) async {
    writes.add('upsertAccountWithSeed');
  }

  @override
  Future<void> updateAccount(AccountEntity account) async {
    writes.add('updateAccount');
  }

  @override
  Future<void> setCurrentAccountId(String? id) async {
    writes.add('setCurrentAccountId');
  }
}

class _RecordingProfileRepository implements ProfileRepositoryPort {
  int fetchCalls = 0;

  @override
  Future<Profile> fetchById(String id) async {
    fetchCalls++;
    return Profile(id: id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedPlatformRepository implements PlatformRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
