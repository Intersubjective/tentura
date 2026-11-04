import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

/// Checks returned values, rather than incidental tokens or all name references.
/// Resolved elements distinguish prefixed imports and same-named functions.
Future<List<String>> excerptDelegationViolations(Uri root) async {
  final paths = [
    root
        .resolve(
          'packages/client/lib/features/beacon_threads/ui/util/room_reply_excerpt.dart',
        )
        .toFilePath(),
    root
        .resolve('packages/server/lib/domain/util/room_reply_excerpt.dart')
        .toFilePath(),
  ];
  final sharedPath = root
      .resolve('lib/domain/util/room_reply_excerpt.dart')
      .toFilePath();
  final contexts = AnalysisContextCollection(
    includedPaths: paths,
    sdkPath: _dartSdkPath(),
  );
  final violations = <String>[];
  final sharedByConsumer = <Set<String>>[];
  try {
    for (final path in paths) {
      final result = await contexts
          .contextFor(path)
          .currentSession
          .getResolvedUnit(path);
      if (result is! ResolvedUnitResult) {
        throw StateError('Could not resolve excerpt consumer $path: $result');
      }
      final functions = {
        for (final node
            in result.unit.declarations.whereType<FunctionDeclaration>())
          node.declaredFragment!.element: node,
      };
      final entry = result.unit.declarations
          .whereType<FunctionDeclaration>()
          .singleWhere((node) => node.name.lexeme == 'roomReplyExcerpt');
      final shared = <String>{};
      final visiting = <Element>{};

      bool forwards(FunctionDeclaration function) {
        final element = function.declaredFragment!.element;
        if (!visiting.add(element)) {
          return false;
        }
        final returns = _ReturnedExpressions();
        function.functionExpression.body.accept(returns);
        final initializers = _Initializers();
        function.functionExpression.body.accept(initializers);
        var valid = returns.expressions.isNotEmpty;

        bool origin(Expression expression, Set<Element> seen) {
          if (expression is NullLiteral) {
            return true;
          }
          if (expression is ParenthesizedExpression) {
            return origin(expression.expression, seen);
          }
          if (expression is ConditionalExpression) {
            final thenValid = origin(expression.thenExpression, {...seen});
            final elseValid = origin(expression.elseExpression, {...seen});
            return thenValid && elseValid;
          }
          if (expression is SimpleIdentifier) {
            final variable = expression.element;
            final value = initializers.values[variable];
            return variable != null &&
                value != null &&
                seen.add(variable) &&
                origin(value, seen);
          }
          if (expression is MethodInvocation) {
            final called = expression.methodName.element;
            if (called == null) return false;
            final fragment = called.firstFragment;
            final source = fragment.libraryFragment?.source.fullName;
            if (source == sharedPath && called is TopLevelFunctionElement) {
              shared.add('$source#${called.name}');
              return true;
            }
            final local = functions[called];
            if (local != null) return forwards(local);
          }
          return false;
        }

        for (final expression in returns.expressions) {
          if (!origin(expression, {})) {
            violations.add(
              '$path#${function.name.lexeme} owns a returned '
              'excerpt instead of forwarding the shared result: '
              '${expression.toSource()}',
            );
            valid = false;
          }
        }
        visiting.remove(element);
        return valid;
      }

      forwards(entry);
      sharedByConsumer.add(shared);
      if (shared.length != 1) {
        violations.add(
          '$path must return the result of one actual shared '
          'truncation declaration; reached $shared',
        );
      }
    }
    if (sharedByConsumer.first.intersection(sharedByConsumer.last).length !=
        1) {
      violations.add(
        'Client and server must return results from the same '
        'declaration in $sharedPath',
      );
    }
    return violations;
  } finally {
    await contexts.dispose();
  }
}

class _ReturnedExpressions extends RecursiveAstVisitor<void> {
  final expressions = <Expression>[];

  @override
  void visitReturnStatement(ReturnStatement node) {
    if (node.expression case final expression?) {
      expressions.add(expression);
    }
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    expressions.add(node.expression);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}
}

class _Initializers extends RecursiveAstVisitor<void> {
  final values = <Element?, Expression>{};

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.initializer case final value?) {
      values[node.declaredFragment?.element] = value;
    }
    super.visitVariableDeclaration(node);
  }
}

// flutter_tester is under engine artifacts, not the Dart SDK. Supply the SDK
// explicitly so the analyzer does not infer the engine folder as its SDK.
String _dartSdkPath() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    for (final suffix in const ['', '/dart-sdk', '/bin/cache/dart-sdk']) {
      final candidate = '${directory.path}$suffix';
      if (File(
        '$candidate/lib/_internal/sdk_library_metadata/lib/libraries.dart',
      ).existsSync()) {
        return candidate;
      }
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Cannot locate the Dart SDK for the delegation guard');
    }
    directory = directory.parent;
  }
}
