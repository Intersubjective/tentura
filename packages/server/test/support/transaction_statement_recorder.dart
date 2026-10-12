import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:test/test.dart';

typedef SelectFixture =
    List<Map<String, Object?>> Function(
      String sql,
      List<Object?> arguments,
    );

/// `expect` that also works outside a test runner (tool/lane_hold_benchmark).
void check(Object? actual, Object? matcher, {String? reason}) {
  final m = wrapMatcher(matcher);
  if (m.matches(actual, <Object?, Object?>{})) return;
  final description = StringDescription();
  m.describe(description);
  throw TestFailure('${reason ?? ''} Expected: $description Actual: $actual');
}

/// Fixed round-trip allowance, independent of the number of batch members.
const transactionStatementBudget = 16;

void expectBoundedTransactions(
  TransactionStatementRecorder recorder, {
  int minimumCommittedBatches = 1,
}) {
  expectSyncOutsideTransactions(recorder);
  check(recorder.transactions, isNotEmpty);
  check(
    recorder.transactions.map((batch) => batch.statements.length),
    everyElement(lessThanOrEqualTo(transactionStatementBudget)),
    reason:
        'Every lane hold must have a constant statement budget; '
        'Drift batching still counts each execution of a statement',
  );
  check(
    recorder.transactions.where((batch) => batch.committed).length,
    greaterThanOrEqualTo(minimumCommittedBatches),
    reason: 'Large workloads must release the DB lane between bounded chunks',
  );
  check(recorder.transactions.any((batch) => batch.rolledBack), isFalse);
}

/// Applies to every measured path, even paths that do not currently sync.
void expectSyncOutsideTransactions(TransactionStatementRecorder recorder) {
  final sync = RegExp(r'\bmr_sync"?\s*\(', caseSensitive: false);
  check(
    recorder.statements.where(
      (statement) =>
          sync.hasMatch(statement.sql) && statement.transaction != null,
    ),
    isEmpty,
    reason: 'No request or sweep transaction may invoke MeritRank sync',
  );
}

/// Checks the whole workload, not just the size of each transaction.
///
/// [maximumBatches] includes header/finalization transactions and deliberately
/// permits a range of implementation-specific chunk sizes. Every member write
/// must carry bulk input (arrays, JSON records, multi-row VALUES, or IN lists).
/// Both the input and the union of IDs written in one transaction are bounded.
/// Thus one transaction per scalar row, or one oversized bulk write, fails.
void expectSetBasedWorkload(
  TransactionStatementRecorder recorder, {
  required Set<String> memberIds,
  required bool Function(String sql) isMemberWrite,
  required int maximumRowsPerBatch,
  int maximumBatches = 16,
  int maximumMemberStatements = 48,
  int maximumSingletonTailsPerWrite = 2,
}) {
  expectSyncOutsideTransactions(recorder);
  final writes = recorder.statements
      .where(
        (statement) => isMemberWrite(statement.sql),
      )
      .toList();
  check(writes, isNotEmpty, reason: 'The workload must execute member writes');
  check(
    writes,
    hasLength(lessThanOrEqualTo(maximumMemberStatements)),
    reason: 'Member writes must scale with bulk chunks, not with row count',
  );
  check(
    recorder.transactions.length,
    lessThanOrEqualTo(maximumBatches),
    reason: 'Committing every row separately is not bounded bulk batching',
  );
  check(
    recorder.statements.length,
    lessThanOrEqualTo(maximumBatches * transactionStatementBudget),
    reason:
        'Total round trips must scale with bulk chunks, not individual rows',
  );
  final bulkSyntax = RegExp(
    r'\bunnest\s*\(|\bany\s*\(|'
    r'\bjsonb?_(?:to_recordset|array_elements)\w*\s*\(|'
    r'\bvalues\s*\([\s\S]*\)\s*,\s*\(|'
    r'\bin\s*\([^)]*\$\d+[^)]*,',
    caseSensitive: false,
  );
  final covered = <String>{};
  final byTransaction = <RecordedTransaction, Set<String>>{};
  final singletonTails = <String, int>{};
  var multiMemberWrites = 0;
  for (final statement in writes) {
    final ids = referencedMemberIds(statement.arguments, memberIds);
    check(
      bulkSyntax.hasMatch(statement.sql),
      isTrue,
      reason: 'Member mutations must use set-based bulk SQL: ${statement.sql}',
    );
    check(ids, isNotEmpty, reason: 'Bulk writes must contain workload members');
    check(
      ids.length,
      lessThanOrEqualTo(maximumRowsPerBatch),
      reason: 'A set-based write must still have bounded input cardinality',
    );
    check(statement.transaction, isNotNull);
    if (ids.length == 1) {
      // One final row is legitimate (e.g. 1201 = 6 * 200 + 1). A stream of
      // single-element unnest/ANY calls is still a per-row implementation.
      final mutation = RegExp(
        r'\b(insert\s+into|update|delete\s+from)\s+([\w".]+)',
        caseSensitive: false,
      ).firstMatch(statement.sql);
      final family = mutation == null
          ? 'projection'
          : '${mutation[1]} ${mutation[2]}'.toLowerCase();
      singletonTails.update(family, (count) => count + 1, ifAbsent: () => 1);
    } else {
      multiMemberWrites++;
    }
    covered.addAll(ids);
    byTransaction
        .putIfAbsent(statement.transaction!, () => <String>{})
        .addAll(ids);
  }
  check(covered, containsAll(memberIds), reason: 'No members may be omitted');
  if (memberIds.length > 1) {
    check(
      multiMemberWrites,
      greaterThan(0),
      reason: 'Bulk SQL must actually mutate several members in one execution',
    );
    check(
      singletonTails.values,
      everyElement(lessThanOrEqualTo(maximumSingletonTailsPerWrite)),
      reason: 'Only a bounded final remainder may use single-member bulk input',
    );
  }
  check(
    byTransaction.values.map((ids) => ids.length),
    everyElement(lessThanOrEqualTo(maximumRowsPerBatch)),
    reason: 'Multiple bulk writes may not hide an oversized lane hold',
  );
  check(
    byTransaction.length,
    greaterThanOrEqualTo((memberIds.length / maximumRowsPerBatch).ceil()),
    reason: 'Large workloads must commit separate bounded member chunks',
  );
  check(
    byTransaction.keys.every((transaction) => transaction.committed),
    isTrue,
    reason: 'Only committed member batches count as lane releases',
  );
}

/// Handles scalar placeholders, PostgreSQL arrays, and JSON record payloads.
Set<String> referencedMemberIds(Iterable<Object?> input, Set<String> members) {
  final found = <String>{};
  void visit(Object? value) {
    if (value is String) {
      if (members.contains(value)) found.add(value);
      final trimmed = value.trimLeft();
      if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
        try {
          visit(jsonDecode(value));
        } on FormatException {
          // A scalar string is not necessarily a JSON payload.
        }
      }
    } else if (value is Map) {
      value.values.forEach(visit);
    } else if (value is Iterable) {
      value.forEach(visit);
    }
  }

  visit(input);
  return found;
}

bool mutatesTable(String sql, String table) => RegExp(
  r'\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+'
  '(?:public\\.)?"?${RegExp.escape(table)}"?\\b',
  caseSensitive: false,
).hasMatch(sql);

/// Scripted PostgreSQL results with real Drift transaction/lane scheduling.
///
/// This counts executions, including each execution in a Drift batch, rather
/// than counting SQL templates. It deliberately does not emulate SQL: existing
/// PostgreSQL repository tests own row semantics and authorization checks.
final class TransactionStatementRecorder extends _StatementExecutor {
  TransactionStatementRecorder({
    required SelectFixture select,
    int Function(String, List<Object?>)? affectedRows,
    Future<void> Function(RecordedStatement)? beforeStatement,
  }) : super(
         _RecorderState(select, affectedRows, beforeStatement),
         null,
       );

  /// Executes the production SQL on PostgreSQL while recording lane holds.
  TransactionStatementRecorder.executing(QueryExecutor executor)
    : super(_RecorderState(null, null, null), null, executor);

  List<RecordedTransaction> get transactions => _state.transactions;
  List<RecordedStatement> get statements => _state.statements;
}

final class RecordedTransaction {
  final statements = <RecordedStatement>[];
  final _clock = Stopwatch();
  bool committed = false;
  bool rolledBack = false;

  Duration get holdTime => _clock.elapsed;
}

final class RecordedStatement {
  const RecordedStatement(this.sql, this.arguments, this.transaction);

  final String sql;
  final List<Object?> arguments;
  final RecordedTransaction? transaction;
}

final class _RecorderState {
  _RecorderState(this.select, this.affectedRows, this.beforeStatement);

  final SelectFixture? select;
  final int Function(String, List<Object?>)? affectedRows;
  final Future<void> Function(RecordedStatement)? beforeStatement;
  final transactions = <RecordedTransaction>[];
  final statements = <RecordedStatement>[];
}

class _StatementExecutor implements QueryExecutor {
  _StatementExecutor(this._state, this._transaction, [this._delegate]);

  final _RecorderState _state;
  final RecordedTransaction? _transaction;
  final QueryExecutor? _delegate;

  @override
  SqlDialect get dialect => SqlDialect.postgres;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async {
    // Drift has acquired the executor lane before opening this transaction.
    // Include BEGIN and the awaited COMMIT in the measured interval.
    _transaction?._clock.start();
    return await _delegate?.ensureOpen(user) ?? true;
  }

  Future<void> _record(String sql, List<Object?> arguments) async {
    final statement = RecordedStatement(
      sql,
      List<Object?>.of(arguments),
      _transaction,
    );
    _state.statements.add(statement);
    _transaction?.statements.add(statement);
    await _state.beforeStatement?.call(statement);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) async {
    await _record(statement, args);
    return _delegate != null
        ? await _delegate.runSelect(statement, args)
        : _state.select!(statement, args);
  }

  Future<int> _write(String statement, List<Object?> args) async {
    await _record(statement, args);
    return _state.affectedRows?.call(statement, args) ?? 1;
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    if (_delegate == null) return _write(statement, args);
    await _record(statement, args);
    return _delegate.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    if (_delegate == null) return _write(statement, args);
    await _record(statement, args);
    return _delegate.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) async {
    if (_delegate == null) return _write(statement, args);
    await _record(statement, args);
    return _delegate.runDelete(statement, args);
  }

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) async {
    await _record(statement, args ?? const []);
    await _delegate?.runCustom(statement, args);
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    for (final execution in statements.arguments) {
      await _record(
        statements.statements[execution.statementIndex],
        execution.arguments,
      );
    }
    await _delegate?.runBatched(statements);
  }

  @override
  TransactionExecutor beginTransaction() {
    final transaction = _transaction ?? RecordedTransaction();
    if (_transaction == null) _state.transactions.add(transaction);
    return _RecordedTransactionExecutor(
      _state,
      transaction,
      nested: _transaction != null,
      delegate: _delegate?.beginTransaction(),
    );
  }

  @override
  QueryExecutor beginExclusive() => _delegate == null
      ? this
      : _StatementExecutor(_state, _transaction, _delegate.beginExclusive());

  @override
  Future<void> close() async {
    await _delegate?.close();
  }
}

final class _RecordedTransactionExecutor extends _StatementExecutor
    implements TransactionExecutor {
  _RecordedTransactionExecutor(
    _RecorderState state,
    RecordedTransaction transaction, {
    required this.nested,
    TransactionExecutor? delegate,
  }) : super(state, transaction, delegate);

  final bool nested;

  @override
  bool get supportsNestedTransactions =>
      (_delegate as TransactionExecutor?)?.supportsNestedTransactions ?? true;

  @override
  Future<void> send() async {
    await (_delegate as TransactionExecutor?)?.send();
    if (!nested) {
      _transaction!._clock.stop();
      _transaction.committed = true;
    }
  }

  @override
  Future<void> rollback() async {
    await (_delegate as TransactionExecutor?)?.rollback();
    if (!nested) {
      _transaction!._clock.stop();
      _transaction.rolledBack = true;
    }
  }
}
