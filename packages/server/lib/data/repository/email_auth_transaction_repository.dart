import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

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
  }) async {
    final token = generateToken();
    final tokenHash = hashToken(token);
    final expiresAt = DateTime.timestamp().add(expiresIn);
    await _database.into(_database.emailAuthTransactions).insert(
      EmailAuthTransactionsCompanion.insert(
        tokenHash: tokenHash,
        normalizedEmail: normalizedEmail,
        inviteCode: inviteCode == null || inviteCode.isEmpty
            ? const Value.absent()
            : Value(inviteCode),
        expiresAt: PgDateTime(expiresAt),
        userAgentHash: userAgentHash,
        ipHash: ipHash,
      ),
    );
    return token;
  }

  @override
  Future<EmailAuthTransactionEntity?> consumeByToken(
    String plaintextToken,
  ) async {
    if (plaintextToken.isEmpty) return null;
    final tokenHash = hashToken(plaintextToken);
    final rows = await _database.customSelect(
      '''
UPDATE public.email_auth_transaction
SET consumed_at = now()
WHERE token_hash = \$1
  AND consumed_at IS NULL
  AND expires_at > now()
RETURNING id, normalized_email, invite_code, created_at, expires_at
''',
      variables: [Variable<String>(tokenHash)],
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return EmailAuthTransactionEntity(
      id: row.read<String>('id'),
      normalizedEmail: row.read<String>('normalized_email'),
      inviteCode: row.readNullable<String>('invite_code'),
      createdAt: (row.read<PgDateTime>('created_at')).dateTime,
      expiresAt: (row.read<PgDateTime>('expires_at')).dateTime,
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
