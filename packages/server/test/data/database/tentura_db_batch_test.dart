// The analyzer is only reachable transitively; this is a test-only AST check.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:tentura_server/data/database/tentura_db.dart' hide Expression;
import 'package:test/test.dart';

void main() {
  test(
    'batch fails before invoking the callback or touching the executor',
    () async {
      final executor = _UnusedExecutor();
      final db = TenturaDb.forTest(database: executor);
      addTearDown(db.close);
      var callbackInvoked = false;

      // Exercise dynamic dispatch through Drift's public database API as well.
      final DatabaseConnectionUser database = db;
      await expectLater(
        database.batch((batch) {
          callbackInvoked = true;
          batch.customStatement('SELECT 1');
        }),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('TenturaDb.batch() is forbidden'),
              contains('scoped connection'),
              contains('withTransaction()'),
            ),
          ),
        ),
      );

      expect(callbackInvoked, isFalse);
      expect(executor.calls, isEmpty);
    },
  );

  test('production code never calls Drift batch APIs', () {
    final calls = <String>[
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.endsWith('.g.dart') &&
            !file.path.endsWith('.config.dart'))
          ..._batchCalls(file.path, file.readAsStringSync()),
    ];
    expect(
      calls,
      isEmpty,
      reason:
          'Drift batch() and runBatched() open their own transaction and '
          'prepared statements outside the scoped connection path; any '
          'receiver other than TenturaDb (a DatabaseAccessor, an executor) '
          'would also skip the TenturaDb.batch override.',
    );
  });

  test('the batch API scan reports calls and ignores mentions', () {
    expect(
      _batchCalls('probe.dart', '''
        class R {
          void f() {
            _db.batch((b) {});
            accessor.batch((b) {});
            executor.runBatched(statements);
            super.runBatched(statements);
            final commit = db.resolvedEngine.batch;
            final run = executor.runBatched;
            print('TenturaDb.batch() is forbidden');
            final batch = 1;
          }
        }
      '''),
      [
        'probe.dart: _db.batch',
        'probe.dart: accessor.batch',
        'probe.dart: executor.runBatched',
        'probe.dart: db.resolvedEngine.batch',
        'probe.dart: executor.runBatched',
      ],
    );
  });
}

List<String> _batchCalls(String path, String source) {
  final visitor = _BatchCallVisitor(path);
  parseString(
    content: source,
    path: path,
    throwIfDiagnostics: false,
  ).unit.accept(visitor);
  return visitor.calls;
}

class _BatchCallVisitor extends RecursiveAstVisitor<void> {
  _BatchCallVisitor(this._path);

  final String _path;
  final calls = <String>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    // An executor wrapper forwarding its own override is not a new caller.
    if ((name == 'batch' || name == 'runBatched') &&
        node.target is! SuperExpression) {
      calls.add('$_path: ${node.target?.toSource() ?? ''}.$name');
    }
    super.visitMethodInvocation(node);
  }

  // A torn-off `x.batch` or `x.runBatched` is a call waiting to happen.
  @override
  void visitPropertyAccess(PropertyAccess node) {
    _tearOff(node.target, node.propertyName.name);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _tearOff(node.prefix, node.identifier.name);
    super.visitPrefixedIdentifier(node);
  }

  void _tearOff(Expression? target, String name) {
    if ((name == 'batch' || name == 'runBatched') &&
        target is! SuperExpression) {
      calls.add('$_path: ${target?.toSource() ?? ''}.$name');
    }
  }
}

/// Any attempt to open, transact, prepare or execute SQL fails this test.
class _UnusedExecutor implements QueryExecutor {
  final List<Symbol> calls = [];

  @override
  SqlDialect get dialect => SqlDialect.postgres;

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError('Unexpected executor call: ${invocation.memberName}');
  }
}
