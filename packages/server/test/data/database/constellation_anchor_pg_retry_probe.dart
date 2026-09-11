import 'package:postgres/postgres.dart';

/// Test-only SQL helpers for P02 repository deadlock-retry proofs against a
/// disposable PostgreSQL database. Not used in production code.
enum ConstellationAnchorDeadlockProbeMode {
  /// Raises `40P01` on the first anchor row mutation in the database session
  /// sequence (non-transactional), then allows later attempts.
  failFirstMutation,

  /// Raises `40P01` on every anchor row mutation (retry exhaustion).
  failAlways,
}

Future<void> installConstellationAnchorDeadlockProbe(
  Connection connection, {
  required ConstellationAnchorDeadlockProbeMode mode,
}) async {
  await connection.execute('CREATE SCHEMA IF NOT EXISTS p02_retry_probe');
  await connection.execute('''
CREATE SEQUENCE IF NOT EXISTS p02_retry_probe.mutation_seq
''');
  final failCondition = switch (mode) {
    ConstellationAnchorDeadlockProbeMode.failFirstMutation =>
      '_n = 1',
    ConstellationAnchorDeadlockProbeMode.failAlways => 'true',
  };
  await connection.execute('''
CREATE OR REPLACE FUNCTION p02_retry_probe.raise_on_anchor_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS \$\$
DECLARE
  _n bigint;
BEGIN
  _n := nextval('p02_retry_probe.mutation_seq');
  IF $failCondition THEN
    RAISE EXCEPTION USING
      ERRCODE = '40P01',
      MESSAGE = 'p02_retry_probe synthetic deadlock',
      DETAIL = format('mutation_seq=%s', _n);
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
\$\$;
''');
  await connection.execute('''
DROP TRIGGER IF EXISTS constellation_anchor_p02_deadlock_probe_trg
  ON public.constellation_anchor
''');
  await connection.execute('''
CREATE TRIGGER constellation_anchor_p02_deadlock_probe_trg
  BEFORE INSERT OR UPDATE OR DELETE ON public.constellation_anchor
  FOR EACH ROW
  EXECUTE FUNCTION p02_retry_probe.raise_on_anchor_mutation()
''');
}

Future<void> resetConstellationAnchorDeadlockProbe(Connection connection) async {
  await connection.execute('''
ALTER SEQUENCE p02_retry_probe.mutation_seq RESTART WITH 1
''');
}

Future<void> uninstallConstellationAnchorDeadlockProbe(
  Connection connection,
) async {
  await connection.execute('''
DROP TRIGGER IF EXISTS constellation_anchor_p02_deadlock_probe_trg
  ON public.constellation_anchor
''');
  await connection.execute('''
DROP FUNCTION IF EXISTS p02_retry_probe.raise_on_anchor_mutation()
''');
}

Future<int> readConstellationAnchorDeadlockProbeMutationSeq(
  Connection connection,
) async {
  final row = await connection.execute('''
SELECT last_value::bigint FROM p02_retry_probe.mutation_seq
''');
  final value = row.single.single;
  return value is BigInt ? value.toInt() : value as int;
}

bool isServerExceptionSqlState(Object error, String sqlState) {
  if (error is! ServerException) {
    return false;
  }
  return error.code == sqlState;
}
