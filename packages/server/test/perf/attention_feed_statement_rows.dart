import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

/// One SELECT as the server ran it: its text, arguments, result and time.
final class CapturedStatement {
  CapturedStatement(this.sql, this.arguments, this.rows, this.elapsedMs);

  final String sql;
  final List<Object?> arguments;
  final List<Map<String, Object?>> rows;
  final double elapsedMs;

  /// The AttentionFeed page statement is the one that answers the feed
  /// summary: every row it returns carries `unread_total` and
  /// `needs_you_total` next to the page columns.
  bool get isFeedStatement =>
      rows.isNotEmpty &&
      rows.first.containsKey('unread_total') &&
      rows.first.containsKey('needs_you_total');
}

/// Records every SELECT issued through a [TenturaDb] scope.
final class StatementRowCapture extends QueryInterceptor {
  final statements = <CapturedStatement>[];

  void clear() => statements.clear();

  /// Captured feed statements, in issue order.
  List<CapturedStatement> get feedStatements => [
    for (final s in statements)
      if (s.isFeedStatement) s,
  ];

  /// Rows of the single feed statement issued since the last [clear].
  List<Map<String, Object?>> feedStatementRows() {
    final feed = feedStatements;
    expect(
      feed,
      hasLength(1),
      reason:
          'One AttentionFeed read must issue exactly one statement answering '
          'the feed summary and page.',
    );
    return feed.single.rows;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final clock = Stopwatch()..start();
    final rows = await executor.runSelect(statement, args);
    statements.add(
      CapturedStatement(
        statement,
        List.of(args),
        rows,
        clock.elapsedMicroseconds / 1000,
      ),
    );
    return rows;
  }
}

/// Same rows, same order, same values for every column the pre-fix statement
/// returned. Extra columns a rewrite adds are ignored; a missing or changed
/// one is a difference.
void expectSameFeedRows({
  required List<Map<String, Object?>> actual,
  required List<Map<String, Object?>> expected,
  required String reason,
}) {
  expect(
    [for (final row in actual) _project(row, expected.firstOrNull)],
    equals([for (final row in expected) _project(row, row)]),
    reason: reason,
  );
}

Map<String, Object?> _project(
  Map<String, Object?> row,
  Map<String, Object?>? columns,
) => {
  for (final key in (columns ?? row).keys)
    key: row.containsKey(key) ? _normalize(row[key]) : '<missing column>',
};

Object? _normalize(Object? value) =>
    value is DateTime ? value.toUtc().toIso8601String() : value;
