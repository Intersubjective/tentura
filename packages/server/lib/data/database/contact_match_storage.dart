import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart';

import 'package:tentura_server/domain/entity/verified_contact_entity.dart';
import 'package:tentura_server/domain/port/verified_contact_rekey_port.dart';
import 'package:tentura_server/domain/util/contact_match_key_ring.dart';
import 'package:tentura_server/domain/util/email_auth_util.dart';
import 'package:tentura_server/env.dart';

import 'main_db_pool.dart';
import 'main_db_scope_admission.dart';

const _verifiedContacts = 'account_verified_contact';
const _contactTables = [_verifiedContacts, 'phantom_contact_point'];

const verifiedEmailMatchRowsSql =
    '''
FROM unnest(\$1::smallint[], \$2::bytea[]) AS candidate(version, digest)
JOIN public.$_verifiedContacts AS contact
  ON contact.hmac_key_version = candidate.version
 AND contact.match_hmac = candidate.digest
 AND contact.kind = 'email'
''';

List<TypedValue> verifiedEmailMatchParameters(
  List<ContactMatchHash> hashes,
) => [
  TypedValue(Type.smallIntegerArray, [for (final hash in hashes) hash.version]),
  TypedValue(Type.byteArrayArray, [
    for (final hash in hashes) hash.digest.bytes,
  ]),
];

@LazySingleton(as: VerifiedContactRekeyPort)
final class VerifiedContactRekey implements VerifiedContactRekeyPort {
  VerifiedContactRekey(this._database, Env env)
    : _keyRing = env.contactMatchKeyRing;

  final MainDbPool _database;
  final ContactMatchKeyRing _keyRing;

  @override
  Future<void> rekey() => _updateVerifiedEmailHashes(
    _database.pool,
    _keyRing,
    backfill: false,
    admission: _database.admission,
  );
}

/// Fill missing email hashes after migrating, preserving all existing hashes.
Future<void> backfillVerifiedContactHashes(
  Connection connection,
  ContactMatchKeyRing keyRing,
) => _updateVerifiedEmailHashes(connection, keyRing, backfill: true);

Future<void> _updateVerifiedEmailHashes(
  SessionExecutor database,
  ContactMatchKeyRing keyRing, {
  required bool backfill,
  MainDbScopeAdmission? admission,
}) async {
  final version = keyRing.newestVersion;
  if (version == null) return;

  String? after;
  while (true) {
    // Lock each page through the update so concurrent runs cannot overwrite
    // a newer digest or hash a value that has changed since it was read.
    Future<String?> updateBatch() => database.runTx((transaction) async {
      final rows = await transaction.execute(
        Sql.named('''
SELECT id, value
FROM public.$_verifiedContacts
WHERE kind = 'email'
  AND (@after::text IS NULL OR id > @after)
  AND CASE WHEN @backfill::boolean THEN match_hmac IS NULL
           ELSE hmac_key_version < @version::smallint END
ORDER BY id
LIMIT 256
FOR UPDATE
'''),
        parameters: {'after': after, 'backfill': backfill, 'version': version},
      );
      if (rows.isEmpty) return null;

      final ids = <String>[];
      final digests = <List<int>>[];
      for (final row in rows) {
        final (id, email) = switch (row) {
          [final String id, final String value] => (id, value),
          _ => throw StateError('Expected a verified email contact.'),
        };
        ids.add(id);
        digests.add(
          keyRing
              .hashNormalizedEmailForWrite(normalizeAuthEmail(email))
              .digest
              .bytes,
        );
      }

      await transaction.execute(
        Sql.named('''
UPDATE public.$_verifiedContacts AS contact
SET match_hmac = candidate.digest, hmac_key_version = @version::smallint
FROM unnest(@ids::text[], @digests::bytea[]) AS candidate(id, digest)
WHERE contact.id = candidate.id
'''),
        parameters: {
          'version': version,
          'ids': TypedValue(Type.textArray, ids),
          'digests': TypedValue(Type.byteArrayArray, digests),
        },
      );
      return ids.last;
    });

    final next = await (admission == null
        ? updateBatch()
        : admission.run(updateBatch, kind: MainDbWorkKind.full));
    if (next == null) return;
    after = next;
  }
}

/// Checks whether retiring a key would strand any stored contact hash.
Future<void> checkStoredContactMatchKeys(
  Connection connection,
  ContactMatchKeyRing keyRing,
) async {
  final versions = await connection.runTx((session) async {
    // Fail closed if the startup role would silently miss rows behind RLS.
    await session.execute('SET LOCAL row_security = off');
    return _referencedVersions(session, await _versionedTables(session));
  });
  final missing = versions.difference(keyRing.versions.toSet()).toList()
    ..sort();
  if (missing.isNotEmpty) {
    throw StateError(
      '${ContactMatchKeyRing.envName} is missing stored key versions: '
      '${missing.join(', ')}.',
    );
  }
}

/// Internal lookup of verified contacts. Callers apply visibility policy.
Future<Set<String>> findMatchingVerifiedAccounts(
  SessionExecutor database,
  ContactMatchKeyRing keyRing, {
  required ContactKind kind,
  required String value,
}) async {
  if (kind != ContactKind.email) return {};
  return database.runTx(
    (session) async {
      final tables = await _versionedTables(session);
      if (!tables.contains(_verifiedContacts)) return <String>{};
      final versions = await _referencedVersions(session, tables);
      final hashes = keyRing.candidateHashes(kind, value, versions).toList();
      if (hashes.isEmpty) return <String>{};
      final rows = await session.execute(
        'SELECT DISTINCT contact.account_id $verifiedEmailMatchRowsSql',
        parameters: verifiedEmailMatchParameters(hashes),
      );
      return {
        for (final row in rows)
          switch (row.single) {
            final String accountId => accountId,
            _ => throw StateError('Expected a verified contact account ID.'),
          },
      };
    },
    settings: TransactionSettings(
      isolationLevel: IsolationLevel.repeatableRead,
      accessMode: AccessMode.readOnly,
    ),
  );
}

Future<List<String>> _versionedTables(Session session) async {
  final columns = await session.execute('''
SELECT relation.relname::text
FROM pg_catalog.pg_class AS relation
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
JOIN pg_catalog.pg_attribute AS column_info ON column_info.attrelid = relation.oid
WHERE namespace.nspname = 'public'
  AND column_info.attname = 'hmac_key_version'
  AND NOT column_info.attisdropped
''');
  final names = {for (final row in columns) row.single};
  return _contactTables.where(names.contains).toList();
}

Future<Set<int>> _referencedVersions(
  Session session,
  List<String> tables,
) async {
  if (tables.isEmpty) return {};
  final rows = await session.execute(
    tables
        .map(
          (table) =>
              '''
SELECT DISTINCT hmac_key_version FROM public.$table
WHERE hmac_key_version IS NOT NULL
''',
        )
        .join('UNION\n'),
  );
  return {
    for (final row in rows)
      switch (row.single) {
        final int version => version,
        _ => throw StateError('Expected an integer contact match key version.'),
      },
  };
}
