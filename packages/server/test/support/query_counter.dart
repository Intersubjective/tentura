import 'package:drift/drift.dart';

/// Counts every Drift-issued statement on an intercepted [QueryExecutor],
/// including the BEGIN/COMMIT that `TenturaDb.withMutatingUser` wraps its
/// action in (plan §14.7 "RT counting").
class QueryCounter extends QueryInterceptor {
  int _count = 0;

  int get count => _count;

  void reset() => _count = 0;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    _count++;
    return super.beginTransaction(parent);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    _count++;
    return super.commitTransaction(inner);
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    _count++;
    return super.runBatched(executor, statements);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _count++;
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _count++;
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _count++;
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _count++;
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _count++;
    return super.runSelect(executor, statement, args);
  }
}
