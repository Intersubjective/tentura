import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart' hide isNull, isNotNull;
import 'package:tentura_server/data/repository/email_auth_transaction_repository.dart';
import 'package:tentura_server/env.dart';

/// Exercises real drift `customSelect` against Postgres (skipped when DB down).
void main() {
  var postgresReachable = false;
  var schemaCurrent = false;
  late TenturaDb db;
  late EmailAuthTransactionRepository repo;

  setUpAll(() async {
    postgresReachable = await _canConnectPostgres();
    if (!postgresReachable) return;
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
    schemaCurrent = await _hasLinkAccountIdColumn(db);
    if (!schemaCurrent) {
      await db.customStatement(
        r'ALTER TABLE public.email_auth_transaction ADD COLUMN link_account_id text',
      );
      schemaCurrent = true;
    }
  });

  tearDownAll(() async {
    if (!postgresReachable) return;
    await db.close();
  });

  tearDown(() async {
    if (!postgresReachable) return;
    await db.customStatement(
      r"DELETE FROM public.email_auth_transaction WHERE normalized_email LIKE 'consume-test-%'",
    );
  });

  test(
    'consumeByToken returns consumed row without reading timestamptz columns',
    () async {
      if (!postgresReachable) {
        markTestSkipped('local Postgres not reachable');
      }
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
  );

  test('consumeByToken returns null for empty token', () async {
    if (!postgresReachable) {
      markTestSkipped('local Postgres not reachable');
    }
    expect(await repo.consumeByToken(''), isNull);
  });
}

Future<bool> _hasLinkAccountIdColumn(TenturaDb db) async {
  final rows = await db.customSelect(
    r'''
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
