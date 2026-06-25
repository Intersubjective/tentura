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
    'hashToken is deterministic SHA-256 hex',
    () {
      const token = 'magic-link-token';
      expect(
        EmailAuthTransactionRepository.hashToken(token),
        EmailAuthTransactionRepository.hashToken(token),
      );
      expect(EmailAuthTransactionRepository.hashToken(token), isNotEmpty);
    },
  );

  test(
    'generateToken returns distinct opaque values',
    () {
      final a = EmailAuthTransactionRepository.generateToken();
      final b = EmailAuthTransactionRepository.generateToken();
      expect(a, isNotEmpty);
      expect(b, isNotEmpty);
      expect(a, isNot(equals(b)));
    },
  );

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

  test(
    'peekByToken returns missing for empty or unknown token',
    () async {
      expect(
        await repo.peekByToken(''),
        (status: EmailAuthTokenStatus.missing, tx: null),
      );
      expect(
        await repo.peekByToken('not-a-real-token'),
        (status: EmailAuthTokenStatus.missing, tx: null),
      );
    },
    skip: skipReason,
  );

  test(
    'peekByToken returns expired without consuming',
    () async {
      const email = 'consume-test-expired@example.com';
      final token = await repo.create(
        normalizedEmail: email,
        expiresIn: const Duration(seconds: -1),
        userAgentHash: 'ua-hash',
        ipHash: 'ip-hash',
      );

      final peek = await repo.peekByToken(token);
      expect(peek.status, EmailAuthTokenStatus.expired);
      expect(peek.tx?.normalizedEmail, email);

      expect(await repo.consumeByToken(token), isNull);
    },
    skip: skipReason,
  );

  test(
    'consumeByToken returns null for unknown or expired token',
    () async {
      expect(await repo.consumeByToken('unknown-token'), isNull);

      final expiredToken = await repo.create(
        normalizedEmail: 'consume-test-expired-consume@example.com',
        expiresIn: const Duration(seconds: -1),
        userAgentHash: 'ua-hash',
        ipHash: 'ip-hash',
      );
      expect(await repo.consumeByToken(expiredToken), isNull);
    },
    skip: skipReason,
  );

  test(
    'create persists linkAccountId and explicit transactionId',
    () async {
      const email = 'consume-test-link@example.com';
      const txId = 'Etest_link_tx01';
      const linkAccountId = 'Ulink_account01';
      final token = await repo.create(
        normalizedEmail: email,
        expiresIn: const Duration(minutes: 15),
        userAgentHash: 'ua-hash',
        ipHash: 'ip-hash',
        linkAccountId: linkAccountId,
        transactionId: txId,
      );

      final peek = await repo.peekByToken(token);
      expect(peek.status, EmailAuthTokenStatus.valid);
      expect(peek.tx?.id, txId);
      expect(peek.tx?.linkAccountId, linkAccountId);
      expect(peek.tx?.inviteCode, isNull);
    },
    skip: skipReason,
  );

  test(
    'create omits empty optional inviteCode and linkAccountId',
    () async {
      const email = 'consume-test-empty-opt@example.com';
      final token = await repo.create(
        normalizedEmail: email,
        expiresIn: const Duration(minutes: 15),
        userAgentHash: 'ua-hash',
        ipHash: 'ip-hash',
        inviteCode: '',
        linkAccountId: '',
      );

      final peek = await repo.peekByToken(token);
      expect(peek.tx?.inviteCode, isNull);
      expect(peek.tx?.linkAccountId, isNull);
    },
    skip: skipReason,
  );

  test(
    'countRecentByEmail counts rows inside the window only',
    () async {
      const email = 'consume-test-count-email@example.com';
      const window = Duration(hours: 1);

      expect(
        await repo.countRecentByEmail(normalizedEmail: email, window: window),
        0,
      );

      await repo.create(
        normalizedEmail: email,
        expiresIn: const Duration(minutes: 15),
        userAgentHash: 'ua-hash',
        ipHash: 'ip-hash-a',
      );
      await repo.create(
        normalizedEmail: email,
        expiresIn: const Duration(minutes: 15),
        userAgentHash: 'ua-hash',
        ipHash: 'ip-hash-b',
      );

      expect(
        await repo.countRecentByEmail(normalizedEmail: email, window: window),
        2,
      );

      await db.customStatement(
        r'''
UPDATE public.email_auth_transaction
SET created_at = now() - interval '2 hours'
WHERE id = (
  SELECT id FROM public.email_auth_transaction
  WHERE normalized_email = $1
  LIMIT 1
)
''',
        [email],
      );

      expect(
        await repo.countRecentByEmail(normalizedEmail: email, window: window),
        1,
      );
    },
    skip: skipReason,
  );

  test(
    'countRecentByIpHash counts rows inside the window only',
    () async {
      const ipHash = 'consume-test-ip-hash';
      const window = Duration(hours: 1);

      await repo.create(
        normalizedEmail: 'consume-test-count-ip-1@example.com',
        expiresIn: const Duration(minutes: 15),
        userAgentHash: 'ua-hash',
        ipHash: ipHash,
      );
      await repo.create(
        normalizedEmail: 'consume-test-count-ip-2@example.com',
        expiresIn: const Duration(minutes: 15),
        userAgentHash: 'ua-hash',
        ipHash: ipHash,
      );

      expect(
        await repo.countRecentByIpHash(ipHash: ipHash, window: window),
        2,
      );

      await db.customStatement(
        r'''
UPDATE public.email_auth_transaction
SET created_at = now() - interval '2 hours'
WHERE id = (
  SELECT id FROM public.email_auth_transaction
  WHERE ip_hash = $1
  LIMIT 1
)
''',
        [ipHash],
      );

      expect(
        await repo.countRecentByIpHash(ipHash: ipHash, window: window),
        1,
      );
    },
    skip: skipReason,
  );

  test(
    'countRecentByInviteCode counts rows inside the window only',
    () async {
      const inviteCode = 'consume-test-invite';
      const window = Duration(hours: 1);

      await repo.create(
        normalizedEmail: 'consume-test-count-inv-1@example.com',
        expiresIn: const Duration(minutes: 15),
        userAgentHash: 'ua-hash',
        ipHash: 'ip-hash-1',
        inviteCode: inviteCode,
      );
      await repo.create(
        normalizedEmail: 'consume-test-count-inv-2@example.com',
        expiresIn: const Duration(minutes: 15),
        userAgentHash: 'ua-hash',
        ipHash: 'ip-hash-2',
        inviteCode: inviteCode,
      );

      expect(
        await repo.countRecentByInviteCode(inviteCode: inviteCode, window: window),
        2,
      );

      await db.customStatement(
        r'''
UPDATE public.email_auth_transaction
SET created_at = now() - interval '2 hours'
WHERE id = (
  SELECT id FROM public.email_auth_transaction
  WHERE invite_code = $1
  LIMIT 1
)
''',
        [inviteCode],
      );

      expect(
        await repo.countRecentByInviteCode(inviteCode: inviteCode, window: window),
        1,
      );
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
