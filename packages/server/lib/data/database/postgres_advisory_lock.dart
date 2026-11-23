import 'postgres_serialization_retry.dart';
import 'tentura_db.dart';

const _advisoryKey = r'hashtextextended($1, 4242)';

Future<void> lockAdvisoryScope(TenturaDb db, String name) => db.customStatement(
  'SELECT pg_advisory_xact_lock($_advisoryKey)',
  [name],
);

/// Wait for the holder to finish, then discard the snapshot taken by try-lock.
Future<void> lockAdvisoryScopeForSnapshot(TenturaDb db, String name) async {
  final row = await db
      .customSelect(
        'SELECT pg_try_advisory_xact_lock($_advisoryKey) AS acquired',
        variables: [Variable<String>(name)],
      )
      .getSingle();
  if (row.read<bool>('acquired')) return;
  await lockAdvisoryScope(db, name);
  throw PostgresSnapshotUnavailableException(
    StateError('The snapshot predates the advisory lock wait'),
  );
}
