import 'package:postgres/postgres.dart';

import 'package:tentura_server/domain/entity/verified_contact_entity.dart';
import 'package:tentura_server/domain/util/contact_match_key_ring.dart';

const _verifiedContacts = 'account_verified_contact';
const _contactTables = [_verifiedContacts, 'phantom_contact_point'];

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
        Sql.named('''
SELECT DISTINCT contact.account_id
FROM unnest(@versions::smallint[], @digests::bytea[]) AS candidate(version, digest)
JOIN public.$_verifiedContacts AS contact
  ON contact.hmac_key_version = candidate.version
 AND contact.match_hmac = candidate.digest
WHERE contact.kind = 'email'
'''),
        parameters: {
          'versions': TypedValue(Type.smallIntegerArray, [
            for (final hash in hashes) hash.version,
          ]),
          'digests': TypedValue(Type.byteArrayArray, [
            for (final hash in hashes) hash.digest.bytes,
          ]),
        },
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
