import 'package:drift/drift.dart' hide isNotNull, isNull;

/// Counts the nested transactions Drift begins on an executor that is already
/// inside a transaction. On PostgreSQL each one is a `SAVEPOINT`.
///
/// Drift's table managers wrap a single `getSingle`/`getSingleOrNull` in a
/// transaction of their own. That savepoint belongs to the framework, not to a
/// repository transaction boundary, so it is not counted.
final class SavepointCountingInterceptor extends QueryInterceptor {
  int savepoints = 0;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    if (parent is TransactionExecutor &&
        !StackTrace.current.toString().contains('BaseTableManager.')) {
      savepoints++;
    }
    return super.beginTransaction(parent);
  }
}
