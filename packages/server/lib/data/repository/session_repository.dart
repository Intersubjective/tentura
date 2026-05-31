import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/account_session_entity.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';

import '../database/tentura_db.dart';

@Singleton(
  as: SessionRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class SessionRepository implements SessionRepositoryPort {
  const SessionRepository(this._database);

  final TenturaDb _database;

  static String hashToken(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  static String generateToken() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }

  @override
  Future<({String token, AccountSessionEntity session})> create({
    required String accountId,
    required Duration expiresIn,
    String? credentialId,
  }) async {
    final token = generateToken();
    final tokenHash = hashToken(token);
    final expiresAt = DateTime.timestamp().add(expiresIn);
    final row = await _database.managers.accountSessions.createReturning(
      (o) => o(
        accountId: accountId,
        tokenHash: tokenHash,
        credentialId: credentialId == null
            ? const Value.absent()
            : Value(credentialId),
        expiresAt: PgDateTime(expiresAt),
      ),
    );
    return (
      token: token,
      session: _toEntity(row),
    );
  }

  @override
  Future<AccountSessionEntity?> findActiveByTokenHash(String tokenHash) async {
    final row = await _database.managers.accountSessions
        .filter((e) => e.tokenHash(tokenHash))
        .getSingleOrNull();
    if (row == null) return null;
    final entity = _toEntity(row);
    if (!entity.isActive) return null;
    return entity;
  }

  @override
  Future<void> revokeByTokenHash(String tokenHash) =>
      _database.managers.accountSessions
          .filter((e) => e.tokenHash(tokenHash))
          .update(
            (o) => o(revokedAt: Value(PgDateTime(DateTime.timestamp()))),
          );

  @override
  Future<void> revokeAllForAccount(String accountId) =>
      _database.managers.accountSessions
          .filter(
            (e) => e.accountId.id(accountId) & e.revokedAt.isNull(),
          )
          .update(
            (o) => o(revokedAt: Value(PgDateTime(DateTime.timestamp()))),
          );

  AccountSessionEntity _toEntity(AccountSession row) => AccountSessionEntity(
    id: row.id,
    accountId: row.accountId,
    tokenHash: row.tokenHash,
    credentialId: row.credentialId,
    createdAt: row.createdAt.dateTime,
    expiresAt: row.expiresAt.dateTime,
    revokedAt: row.revokedAt?.dateTime,
  );
}
