import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Forbids inline GraphQL document strings and `gql('...')` string documents.
final class NoRawGraphqlInDart extends DartLintRule {
  const NoRawGraphqlInDart() : super(code: _code);

  static const _code = LintCode(
    name: 'no_raw_graphql_in_dart',
    problemMessage:
        'Raw GraphQL document strings are forbidden in Dart. Put the operation in '
        'a .graphql file and use the generated *Req class from ferry_generator.',
    // LintCode (custom_lint_core) still requires ErrorSeverity until upstream migrates.
    // ignore: deprecated_member_use
    errorSeverity: ErrorSeverity.ERROR,
  );

  /// GraphQL operation keyword at document start (after optional whitespace).
  static final _documentLead = RegExp(
    r'^\s*(query|mutation|subscription)\s*(\w+\s*)?[({]',
    multiLine: true,
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    final path = resolver.path;
    if (_skipPath(path)) return;

    context.registry.addCompilationUnit((unit) {
      unit.accept(_Visitor(reporter, _code));
    });
  }

  static bool _skipPath(String path) {
    if (path.contains('packages/tentura_lints/')) {
      return true;
    }
    if (path.contains('.g.dart') ||
        path.contains('.gql.dart') ||
        path.contains('.freezed.dart') ||
        path.contains('/generated/')) {
      return true;
    }
    return false;
  }
}

final class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this._reporter, this._code);

  final DiagnosticReporter _reporter;
  final LintCode _code;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (!_skipBecauseUnderGqlCall(node)) {
      final value = node.stringValue;
      if (value != null && NoRawGraphqlInDart._documentLead.hasMatch(value)) {
        _reporter.atNode(node, _code);
      }
    }
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    if (!_skipBecauseUnderGqlCall(node)) {
      final value = node.stringValue;
      if (value != null && NoRawGraphqlInDart._documentLead.hasMatch(value)) {
        _reporter.atNode(node, _code);
      }
    }
    super.visitAdjacentStrings(node);
  }

  /// Avoid double-reporting strings already flagged in [visitMethodInvocation].
  static bool _skipBecauseUnderGqlCall(StringLiteral node) {
    var current = node.parent;
    if (current is AdjacentStrings) {
      current = current.parent;
    }
    if (current is! ArgumentList) {
      return false;
    }
    final inv = current.parent;
    return inv is MethodInvocation && inv.methodName.name == 'gql';
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'gql') {
      final first = _firstPositionalArg(node.argumentList);
      if (first is StringLiteral) {
        final value = first.stringValue;
        if (value != null && value.isNotEmpty) {
          _reporter.atNode(first, _code);
        }
      }
    }
    super.visitMethodInvocation(node);
  }

  static Expression? _firstPositionalArg(ArgumentList list) {
    for (final a in list.arguments) {
      if (a is NamedExpression) {
        continue;
      }
      return a;
    }
    return null;
  }
}
