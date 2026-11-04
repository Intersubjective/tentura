// Test-only AST inspection, shared by the server and client regression tests.
// ignore_for_file: depend_on_referenced_packages
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Inspect a revision consumer, rather than unrelated package literals.
List<String> decimalRevisionValidationViolations(String source) {
  final uses = _PatternUses();
  parseString(content: source).unit.accept(uses);
  return [
    if (uses.ownsDecimalPattern) 'defines a local decimal revision regexp',
    if (!uses.matches.any(
      (target) => uses.dependsOnShared(target, <String>{}),
    ))
      'must validate with the shared decimal pattern (directly or via an alias)',
  ];
}

class _PatternUses extends RecursiveAstVisitor<void> {
  final initializers = <String, Expression>{};
  final matches = <Expression>[];
  final regexpArguments = <Expression>[];

  bool get ownsDecimalPattern => regexpArguments.any(
    (argument) => _stringValue(argument, <String>{}) == r'^[0-9]+$',
  );

  String? _stringValue(Expression expression, Set<String> visited) {
    if (expression is StringLiteral) return expression.stringValue;
    if (expression is SimpleIdentifier && visited.add(expression.name)) {
      final initializer = initializers[expression.name];
      if (initializer != null) return _stringValue(initializer, visited);
    }
    return null;
  }

  bool dependsOnShared(Expression expression, Set<String> visited) {
    if (expression is ParenthesizedExpression) {
      return dependsOnShared(expression.expression, visited);
    }
    if (expression is PrefixedIdentifier) {
      return expression.identifier.name == 'kDecimalRevisionPattern';
    }
    if (expression is SimpleIdentifier) {
      if (expression.name == 'kDecimalRevisionPattern') return true;
      if (!visited.add(expression.name)) return false;
      final initializer = initializers[expression.name];
      return initializer != null && dependsOnShared(initializer, visited);
    }
    if (expression is MethodInvocation &&
        expression.methodName.name == 'RegExp') {
      return expression.argumentList.arguments.any(
        (argument) =>
            dependsOnShared(argument.argumentExpression, {...visited}),
      );
    }
    if (expression is InstanceCreationExpression &&
        expression.constructorName.type.name.lexeme == 'RegExp') {
      return expression.argumentList.arguments.any(
        (argument) =>
            dependsOnShared(argument.argumentExpression, {...visited}),
      );
    }
    return false;
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    if (initializer != null) initializers[node.name.lexeme] = initializer;
    super.visitVariableDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'hasMatch' && node.target != null) {
      matches.add(node.target!);
    }
    if (node.methodName.name == 'RegExp') {
      regexpArguments.addAll(
        node.argumentList.arguments
            .take(1)
            .map((argument) => argument.argumentExpression),
      );
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'RegExp') {
      regexpArguments.addAll(
        node.argumentList.arguments
            .take(1)
            .map((argument) => argument.argumentExpression),
      );
    }
    super.visitInstanceCreationExpression(node);
  }
}
