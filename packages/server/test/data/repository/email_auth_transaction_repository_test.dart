@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart' hide isNotNull, isNull;
import 'package:tentura_server/data/repository/email_auth_transaction_repository.dart';
import 'package:tentura_server/domain/entity/email_auth_peek.dart';
import 'package:tentura_server/env.dart';

/// Postgres integration test — skipped in CI when DB is down.
///
/// See `packages/server/README.md` § Tests for the full list and how to run locally.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  final skipReason =
      postgresReachable ? false : 'local Postgres not reachable';

  late TenturaDb db;
  late EmailAuthTransactionRepository repo;

  if (postgresReachable) {
    setUpAll(() async {
      final env = Env(
        environment: Environment.test,
        pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
        pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
        pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
        printEnv: false,
        isDebugModeOn: false,
      );
      db = TenturaDb(env);
      repo = EmailAuthTransactionRepository(db);
      final schemaCurrent = await _hasLinkAccountIdColumn(db);
      if (!schemaCurrent) {
        await db.customStatement(
          'ALTER TABLE public.email_auth_transaction ADD COLUMN link_account_id text',
        );
      }
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.email_auth_transaction WHERE normalized_email LIKE 'consume-test-%'",
      );
    });
  }

  test(
    'consumeByToken returns consumed row without reading timestamptz columns',
    () async {
      const email = 'consume-test-ok@example.com';
      final token = await repo.create(
        normalizedEmail: email,
        expiresIn: const Duration(minutes: 15),
        userAgentHash: 'ua-hash',
        ipHash: 'ip-hash',
        inviteCode: 'Iinvite',
      );

      final consumed = await repo.consumeByToken(token);

      expect(consumed, isNotNull);
      expect(consumed!.normalizedEmail, email);
      expect(consumed.inviteCode, 'Iinvite');
      expect(await repo.consumeByToken(token), isNull);
    },
    skip: skipReason,
  );

  test(
    'consumeByToken returns null for empty token',
    () async {
      expect(await repo.consumeByToken(''), isNull);
    },
    skip: skipReason,
  );

  test(
    'peekByToken returns status without consuming',
    () async {
      const email = 'consume-test-peek@example.com';
      final token = await repo.create(
        normalizedEmail: email,
        expiresIn: const Duration(minutes: 15),
        userAgentHash: 'ua-hash',
        ipHash: 'ip-hash',
        inviteCode: 'Ipeek',
      );

      final peek1 = await repo.peekByToken(token);
      expect(peek1.status, EmailAuthTokenStatus.valid);
      expect(peek1.tx?.normalizedEmail, email);
      expect(peek1.tx?.inviteCode, 'Ipeek');

      final peek2 = await repo.peekByToken(token);
      expect(peek2.status, EmailAuthTokenStatus.valid);

      final consumed = await repo.consumeByToken(token);
      expect(consumed, isNotNull);

      final peek3 = await repo.peekByToken(token);
      expect(peek3.status, EmailAuthTokenStatus.consumed);
    },
    skip: skipReason,
  );
}

Future<bool> _hasLinkAccountIdColumn(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'email_auth_transaction'
  AND column_name = 'link_account_id'
LIMIT 1
''',
  ).get();
  return rows.isNotEmpty;
}

Future<bool> _canConnectPostgres() async {
  final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
  try {
    final socket = await Socket.connect(host, port).timeout(
      const Duration(seconds: 2),
    );
    await socket.close();
    return true;
  } catch (_) {
    return false;
  }
}
