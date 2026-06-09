import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNull, isNotNull;
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/asserted_contact.dart';
import 'package:tentura_server/env.dart';

/// Verifies linking a credential when the authoritative contact already exists
/// on the same account (e.g. Google signup + email magic link).
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  final skipReason =
      postgresReachable ? false : 'local Postgres not reachable';

  late TenturaDb db;
  late UserRepository repo;
  const accountId = 'UemailLinkTest000000000000000001';
  const email = 'email-link-test@example.com';

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
      repo = UserRepository(env, db);
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        r"DELETE FROM account_credential WHERE account_id = $1",
        [accountId],
      );
      await db.customStatement(
        r"DELETE FROM account_verified_contact WHERE account_id = $1",
        [accountId],
      );
      await db.customStatement(
        r'DELETE FROM "user" WHERE id = $1',
        [accountId],
      );
    });
  }

  test(
    'linkCredentialWithContacts succeeds when verified email already on account',
    () async {
      await db.customStatement(
        r'INSERT INTO "user" (id, display_name, public_key) VALUES ($1, $2, $3)',
        [accountId, 'Link Test', 'pk-email-link-test'],
      );
      await db.customStatement(
        r'INSERT INTO account_credential (id, account_id, type, identifier) '
        r"VALUES ('CgoogleLinkTest01', $1, 'oidc:google', 'google-sub-link-test')",
        [accountId],
      );
      await db.customStatement(
        r'INSERT INTO account_verified_contact '
        r"(id, account_id, kind, value, last_source) "
        r"VALUES ('VgoogleLinkTest01', $1, 'email', $2, 'oidc:google')",
        [accountId, email],
      );

      final linkedAccountId = await repo.linkCredentialWithContacts(
        accountId: accountId,
        type: CredentialType.emailOtp,
        identifier: email,
        contacts: [
          AssertedContact.email(rawEmail: email, authoritative: true)!,
        ],
      );

      expect(linkedAccountId, accountId);
      final credentialId = await repo.findCredentialId(
        type: CredentialType.emailOtp,
        identifier: email,
      );
      expect(credentialId, isNotNull);
    },
    skip: skipReason,
  );
}

Future<bool> _canConnectPostgres() async {
  try {
    final socket = await Socket.connect(
      Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
      int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
      timeout: const Duration(milliseconds: 500),
    );
    await socket.close();
    return true;
  } catch (_) {
    return false;
  }
}
