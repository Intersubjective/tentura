import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/session_repository.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';

import '../support/session_database_di_harness.dart';
import '../support/smoke_env.dart';

final class _RecordingQueryExecutor implements QueryExecutor {
  _RecordingQueryExecutor([List<String>? statements])
    : statements = statements ?? [];

  final List<String> statements;

  @override
  SqlDialect get dialect => SqlDialect.postgres;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => true;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) async {
    statements.add(statement);
    if (statement.contains('account_session') &&
        statements.any(
          (sql) =>
              sql.contains('account_session') &&
              sql.toUpperCase().contains('INSERT'),
        )) {
      // Drift's INSERT RETURNING and follow-up manager reads map SQL values
      // into AccountSession. Supply a valid row without a physical connection.
      final row = <String, Object?>{
        'id': 'Sisolated',
        'account_id': 'Uisolated',
        'token_hash': 'session-token-hash',
        'credential_id': null,
        'created_at': DateTime.utc(2026),
        'expires_at': DateTime.utc(2100),
        'revoked_at': null,
      };
      return [
        {
          ...row,
          for (final entry in row.entries)
            'account_session.${entry.key}': entry.value,
        },
      ];
    }
    return [];
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    statements.add(statement);
    return 1;
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    statements.add(statement);
    return 0;
  }

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) async {
    statements.add(statement);
  }

  @override
  TransactionExecutor beginTransaction() =>
      _RecordingTransactionExecutor(statements);

  @override
  QueryExecutor beginExclusive() => _RecordingQueryExecutor(statements);

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _RecordingTransactionExecutor extends _RecordingQueryExecutor
    implements TransactionExecutor {
  _RecordingTransactionExecutor(super.statements);

  @override
  bool get supportsNestedTransactions => true;

  @override
  Future<void> send() async {}

  @override
  Future<void> rollback() async {}
}

Future<
  ({
    _RecordingQueryExecutor mainExecutor,
    _RecordingQueryExecutor authExecutor,
  })
>
_configureRecordingSessionGraph(String environment) async {
  final mainExecutor = _RecordingQueryExecutor();
  final authExecutor = _RecordingQueryExecutor();
  final mainDatabase = TenturaDb.forTest(database: mainExecutor);
  final authDatabase = TenturaDb.forTest(database: authExecutor);
  addTearDown(mainDatabase.close);
  addTearDown(authDatabase.close);

  // Substitute only the database executors; generated DI still constructs
  // the real SessionRepository and injects it into SessionCase.
  getIt
    ..skipDoubleRegistration = true
    ..registerSingleton<TenturaDb>(mainDatabase)
    ..registerSingleton<TenturaDb>(authDatabase, instanceName: 'auth');
  await configureSessionDatabaseTestGraph(
    environment == Environment.dev ? smokeDevEnv() : smokeProdEnv(),
  );
  return (mainExecutor: mainExecutor, authExecutor: authExecutor);
}

void main() {
  group('Session database isolation in dependency injection', () {
    final previousWarningSetting =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;

    setUpAll(() {
      // These intentionally independent executors do not share connections.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });

    tearDownAll(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousWarningSetting;
    });

    setUp(() async {
      await getIt.reset();
    });

    tearDown(() async {
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
    });

    for (final environment in [Environment.dev, Environment.prod]) {
      test(
        'registers a separate auth database singleton in $environment',
        () async {
          await configureSessionDatabaseTestGraph(
            environment == Environment.dev ? smokeDevEnv() : smokeProdEnv(),
          );
          final mainDatabase = getIt.get<TenturaDb>();
          addTearDown(mainDatabase.close);

          expect(
            getIt.isRegistered<TenturaDb>(instanceName: 'auth'),
            isTrue,
            reason: 'Session traffic needs its own database connection.',
          );
          final authDatabase = getIt.get<TenturaDb>(instanceName: 'auth');
          addTearDown(authDatabase.close);
          expect(authDatabase, isNot(same(mainDatabase)));
          expect(
            getIt.get<TenturaDb>(instanceName: 'auth'),
            same(authDatabase),
          );
          expect(getIt.get<TenturaDb>(), same(mainDatabase));
        },
        tags: ['pg'],
      );

      test(
        'injects the auth database into session creation through the repository '
        'and case in $environment',
        () async {
          final databases = await _configureRecordingSessionGraph(environment);
          final sessions = getIt.get<SessionRepositoryPort>();
          expect(sessions, isA<SessionRepository>());

          final created = await sessions.create(
            accountId: 'Uisolated',
            expiresIn: const Duration(hours: 1),
          );
          expect(created.session.accountId, 'Uisolated');
          expect(created.token, isNotEmpty);
          expect(
            databases.mainExecutor.statements,
            isEmpty,
            reason: 'The DI-bound session repository must insert through auth.',
          );
          expect(
            databases.authExecutor.statements,
            contains(contains('account_session')),
          );
          databases.authExecutor.statements.clear();

          final token = await getIt.get<SessionCase>().createSession(
            accountId: 'Uisolated',
          );
          expect(token, isNotEmpty);
          expect(
            databases.mainExecutor.statements,
            isEmpty,
            reason: 'SessionCase must receive the repository that uses auth.',
          );
          expect(
            databases.authExecutor.statements,
            contains(contains('account_session')),
          );
        },
      );

      test(
        'routes session reads and revocations to auth and user reads to main '
        'in $environment',
        () async {
          final databases = await _configureRecordingSessionGraph(environment);
          final mainExecutor = databases.mainExecutor;
          final authExecutor = databases.authExecutor;
          final sessions = getIt.get<SessionRepositoryPort>();
          expect(sessions, isA<SessionRepository>());

          expect(
            await getIt.get<SessionCase>().resolveAccountId('opaque-token'),
            isNull,
          );
          await sessions.revokeByTokenHash('token-hash');
          await sessions.revokeAllForAccount('Uisolated');
          await sessions.revokeByCredentialId('Cisolated');

          expect(
            mainExecutor.statements,
            isEmpty,
            reason: 'Session operations must never queue on the main database.',
          );
          expect(
            authExecutor.statements,
            contains(contains('account_session')),
          );
          final sessionStatements = List<String>.of(authExecutor.statements);

          expect(
            await getIt.get<UserRepositoryPort>().listCredentials(
              accountId: 'Uisolated',
            ),
            isEmpty,
          );
          expect(
            mainExecutor.statements,
            contains(contains('account_credential')),
          );
          expect(authExecutor.statements, orderedEquals(sessionStatements));
        },
      );
    }
  });
}
