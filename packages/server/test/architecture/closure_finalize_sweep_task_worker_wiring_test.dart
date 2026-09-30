// The analyzer is only reachable transitively; this is a test-only AST check.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// A14 / plan §0.1: the production `TaskWorkerCase.create` factory must take
/// `ClosureFinalizeSweepCase`, forward it, and schedule it every 60 s.

class _FindCreate extends RecursiveAstVisitor<void> {
  MethodDeclaration? create;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == 'create' && node.isStatic) create = node;
    super.visitMethodDeclaration(node);
  }
}

class _FindWorkerCall extends RecursiveAstVisitor<void> {
  final argumentLists = <ArgumentList>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'TaskWorkerCase') {
      argumentLists.add(node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == 'TaskWorkerCase') {
      argumentLists.add(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}

class _FindSweepTask extends RecursiveAstVisitor<void> {
  final closures = <FunctionExpression>[];

  @override
  void visitFunctionExpression(FunctionExpression node) {
    final src = node.body.toSource();
    final inner = closures.any(
      (c) => node.offset >= c.offset && node.end <= c.end,
    );
    if (!inner &&
        src.contains('_closureFinalizeSweep') &&
        src.contains('Duration(')) {
      closures.add(node);
      return;
    }
    super.visitFunctionExpression(node);
  }
}

void main() {
  late CompilationUnit unit;

  setUpAll(() {
    unit = parseString(
      content: File(
        'lib/domain/use_case/task_worker_case.dart',
      ).readAsStringSync(),
    ).unit;
  });

  test('create takes ClosureFinalizeSweepCase and forwards exactly that', () {
    final finder = _FindCreate();
    unit.accept(finder);
    final create = finder.create!;
    final param = create.parameters!.parameters
        .whereType<RegularFormalParameter>()
        .where((p) => p.type.toString() == 'ClosureFinalizeSweepCase')
        .toList();
    expect(param, hasLength(1), reason: 'non-nullable ClosureFinalizeSweepCase');

    final calls = _FindWorkerCall();
    create.body.accept(calls);
    expect(calls.argumentLists, hasLength(1));
    final forwarded = calls.argumentLists.single.arguments
        .whereType<NamedArgument>()
        .where((e) => e.name.lexeme == 'closureFinalizeSweep')
        .toList();
    expect(forwarded, hasLength(1));
    expect(
      (forwarded.single.argumentExpression as SimpleIdentifier).name,
      param.single.name!.lexeme,
    );
  });

  test('the sweep job is scheduled in _tasks with a 60 s cadence', () {
    final finder = _FindSweepTask();
    unit.accept(finder);
    expect(finder.closures, hasLength(1));
    expect(finder.closures.single.body.toSource(), contains('seconds: 60'));
  });
}
