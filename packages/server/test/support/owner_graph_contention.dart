import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:test/test.dart';

import 'disposable_pg_target.dart';

/// The writes under test have a five-second transaction retry budget.
const ownerGraphWriteLimit = Duration(seconds: 6);

/// Starts the competing work outside the holder's transaction and connection.
Future<T> whileOwnerGraphScopeHeld<T>(
  OwnerGraphTransactionPort graph,
  String owner,
  Future<T> Function() compete, {
  Future<void> Function()? beforeCommit,
}) async {
  final entered = Completer<void>();
  final release = Completer<void>();
  final holder = graph.run({owner}, owner, (_) async {
    entered.complete();
    await release.future;
    await beforeCommit?.call();
  })..ignore();

  try {
    await Future.any([
      entered.future,
      holder.then((_) => fail('Owner transaction did not reach its barrier')),
    ]).timeout(ownerGraphWriteLimit);
    return await compete().timeout(ownerGraphWriteLimit);
  } finally {
    release.complete();
    await holder.timeout(ownerGraphWriteLimit);
  }
}

/// Observes a stable lock wait, or reports that the competing work completed
/// while the holder was still in its callback. Unexpected errors propagate.
Future<bool> waitsForOwnerGraphScope<T>(
  Connection observer,
  String owner,
  Future<T> operation,
) async {
  var finished = false;
  final observed = operation.whenComplete(() => finished = true)..ignore();
  final clock = Stopwatch()..start();
  while (!finished && clock.elapsed < ownerGraphWriteLimit) {
    final rows = await observer.execute(
      Sql.named('''
WITH scope AS (SELECT hashtextextended('owner_graph:' || @owner, 4242) AS key)
SELECT EXISTS (
  SELECT 1 FROM pg_locks, scope
  WHERE locktype = 'advisory' AND objsubid = 1 AND NOT granted
    AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
    AND classid::bigint = ((key >> 32) & 4294967295)
    AND objid::bigint = (key & 4294967295)
)
'''),
      parameters: {'owner': owner},
    );
    if (rows.single.single! as bool) return true;
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
  if (!finished) fail('No completion or owner scope wait for $owner');
  await observed;
  return false;
}

/// Future connections to this disposable database exercise the real trigger.
Future<void> enforceOwnerScope(DisposablePgWriterSession session) async {
  final database = session.target.databaseName;
  final writer = session.writer;
  await writer.execute(
    "ALTER DATABASE $database SET tentura.owner_scope_enforce = 'on'",
  );
  addTearDown(
    () => writer.execute(
      'ALTER DATABASE $database RESET tentura.owner_scope_enforce',
    ),
  );
}
