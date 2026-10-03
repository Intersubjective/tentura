import 'package:postgres/postgres.dart';

import 'disposable_pg_target.dart';

/// Contract for serializing `mr`-tagged suites: while such a suite has a
/// disposable database provisioned, one session holds
/// `pg_advisory_lock(hashtext(meritRankSuiteLockKey))` on the admin database.
const meritRankSuiteLockKey = 'tentura_meritrank_suite_exclusive';

/// One non-blocking attempt to take the MeritRank suite lock from a fresh
/// session; true means nobody held it (and it has been released again).
Future<bool> meritRankSuiteLockIsFree(DisposablePgTarget target) async {
  final probe = await Connection.open(
    target.adminEnv.pgEndpoint,
    settings: target.adminEnv.pgEndpointSettings,
  );
  try {
    final row = (await probe.execute(
      Sql.named('SELECT pg_try_advisory_lock(hashtext(@key))'),
      parameters: {'key': meritRankSuiteLockKey},
    )).first;
    final acquired = row.first! as bool;
    if (acquired) {
      await probe.execute(
        Sql.named('SELECT pg_advisory_unlock(hashtext(@key))'),
        parameters: {'key': meritRankSuiteLockKey},
      );
    }
    return acquired;
  } finally {
    await probe.close();
  }
}

/// Polls until the lock is free; false when it stays held for [within].
///
/// Other `mr` suites may legitimately hold the lock in turn, so a single probe
/// right after release is not a reliable "released" signal under parallelism.
Future<bool> meritRankSuiteLockBecomesFree(
  DisposablePgTarget target, {
  Duration within = const Duration(minutes: 2),
}) async {
  final deadline = DateTime.now().add(within);
  while (true) {
    if (await meritRankSuiteLockIsFree(target)) return true;
    if (DateTime.now().isAfter(deadline)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Takes the MeritRank suite lock on a dedicated session, waiting for any
/// `mr` suite that currently holds it; the caller must [Connection.close] the
/// returned session to release it.
Future<Connection> holdMeritRankSuiteLock(DisposablePgTarget target) async {
  final holder = await Connection.open(
    target.adminEnv.pgEndpoint,
    settings: ConnectionSettings(
      sslMode: target.adminEnv.pgEndpointSettings.sslMode,
      queryTimeout: const Duration(minutes: 15),
    ),
  );
  await holder.execute(
    Sql.named('SELECT pg_advisory_lock(hashtext(@key))'),
    parameters: {'key': meritRankSuiteLockKey},
  );
  return holder;
}

/// Sessions currently queued (not granted) on the MeritRank suite lock.
Future<int> meritRankSuiteLockWaiterCount(DisposablePgTarget target) async {
  final probe = await Connection.open(
    target.adminEnv.pgEndpoint,
    settings: target.adminEnv.pgEndpointSettings,
  );
  try {
    final rows = await probe.execute(
      Sql.named('''
SELECT count(*)::int FROM pg_locks
WHERE locktype = 'advisory'
  AND NOT granted
  AND objsubid = 1
  AND classid::bigint = ((hashtext(@key)::bigint >> 32) & 4294967295)
  AND objid::bigint = (hashtext(@key)::bigint & 4294967295)
'''),
      parameters: {'key': meritRankSuiteLockKey},
    );
    return rows.first.first! as int;
  } finally {
    await probe.close();
  }
}
