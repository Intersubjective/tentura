import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/entity/email_auth_peek.dart';
import 'package:tentura_server/domain/entity/email_auth_transaction_entity.dart';
import 'package:tentura_server/domain/port/email_auth_transaction_repository_port.dart';

import '../database/tentura_db.dart';

@Singleton(
  as: EmailAuthTransactionRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class EmailAuthTransactionRepository
    implements EmailAuthTransactionRepositoryPort {
  const EmailAuthTransactionRepository(this._database);

  final TenturaDb _database;

  static String hashToken(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  static String generateToken() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  @override
  Future<String> create({
    required String normalizedEmail,
    required Duration expiresIn,
    required String userAgentHash,
    required String ipHash,
    String? inviteCode,
    String? linkAccountId,
    String? transactionId,
  }) async {
    final token = generateToken();
    final tokenHash = hashToken(token);
    final expiresAt = DateTime.timestamp().add(expiresIn);
    await _database.into(_database.emailAuthTransactions).insert(
      EmailAuthTransactionsCompanion.insert(
        id: transactionId != null && transactionId.isNotEmpty
            ? Value(transactionId)
            : const Value.absent(),
        tokenHash: tokenHash,
        normalizedEmail: normalizedEmail,
        inviteCode: inviteCode == null || inviteCode.isEmpty
            ? const Value.absent()
            : Value(inviteCode),
        linkAccountId: linkAccountId == null || linkAccountId.isEmpty
            ? const Value.absent()
            : Value(linkAccountId),
        expiresAt: PgDateTime(expiresAt),
        userAgentHash: userAgentHash,
        ipHash: ipHash,
      ),
    );
    return token;
  }

  @override
  Future<EmailAuthTokenPeekRow> peekByToken(String plaintextToken) async {
    if (plaintextToken.isEmpty) {
      return (status: EmailAuthTokenStatus.missing, tx: null);
    }
    final tokenHash = hashToken(plaintextToken);
    final rows = await _database.customSelect(
      r'''
SELECT id, normalized_email, invite_code, link_account_id,
       CASE
         WHEN consumed_at IS NOT NULL THEN 'consumed'
         WHEN expires_at <= now() THEN 'expired'
         ELSE 'valid'
       END AS token_status
FROM public.email_auth_transaction
WHERE token_hash = $1
LIMIT 1
''',
      variables: [Variable<String>(tokenHash)],
    ).get();
    if (rows.isEmpty) {
      return (status: EmailAuthTokenStatus.missing, tx: null);
    }
    final row = rows.first;
    final statusWire = row.read<String>('token_status');
    final status = switch (statusWire) {
      'consumed' => EmailAuthTokenStatus.consumed,
      'expired' => EmailAuthTokenStatus.expired,
      _ => EmailAuthTokenStatus.valid,
    };
    return (
      status: status,
      tx: EmailAuthTransactionEntity(
        id: row.read<String>('id'),
        normalizedEmail: row.read<String>('normalized_email'),
        inviteCode: row.readNullable<String>('invite_code'),
        linkAccountId: row.readNullable<String>('link_account_id'),
        createdAt: DateTime.timestamp(),
        expiresAt: DateTime.timestamp(),
      ),
    );
  }

  @override
  Future<EmailAuthTransactionEntity?> consumeByToken(
    String plaintextToken,
  ) async {
    if (plaintextToken.isEmpty) return null;
    final tokenHash = hashToken(plaintextToken);
    final rows = await _database.customSelect(
      r'''
UPDATE public.email_auth_transaction
SET consumed_at = now()
WHERE token_hash = $1
  AND consumed_at IS NULL
  AND expires_at > now()
RETURNING id, normalized_email, invite_code, link_account_id
''',
      variables: [Variable<String>(tokenHash)],
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    final now = DateTime.timestamp();
    return EmailAuthTransactionEntity(
      id: row.read<String>('id'),
      normalizedEmail: row.read<String>('normalized_email'),
      inviteCode: row.readNullable<String>('invite_code'),
      linkAccountId: row.readNullable<String>('link_account_id'),
      createdAt: now,
      expiresAt: now,
    );
  }

  @override
  Future<int> countRecentByEmail({
    required String normalizedEmail,
    required Duration window,
  }) => _countRecent(
    r'normalized_email = $1',
    [normalizedEmail],
    window,
  );

  @override
  Future<int> countRecentByIpHash({
    required String ipHash,
    required Duration window,
  }) => _countRecent(r'ip_hash = $1', [ipHash], window);

  @override
  Future<int> countRecentByInviteCode({
    required String inviteCode,
    required Duration window,
  }) => _countRecent(
    r'invite_code = $1',
    [inviteCode],
    window,
  );

  Future<int> _countRecent(
    String whereClause,
    List<String> args,
    Duration window,
  ) async {
    final since = DateTime.timestamp().subtract(window);
    final rows = await _database.customSelect(
      '''
SELECT COUNT(*)::int AS c
FROM public.email_auth_transaction
WHERE $whereClause AND created_at >= \$2
''',
      variables: [
        Variable<String>(args.first),
        Variable(TypedValue(Type.timestampTz, since)),
      ],
    ).getSingle();
    return rows.read<int>('c');
  }
}
