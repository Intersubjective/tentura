import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Forbids inline GraphQL document strings and `gql('...')` string documents.
final class NoRawGraphqlInDart extends AnalysisRule {
  NoRawGraphqlInDart()
    : super(
        name: 'no_raw_graphql_in_dart',
        description:
            'Raw GraphQL document strings are forbidden in Dart; use .graphql files.',
      );

  static const LintCode code = LintCode(
    'no_raw_graphql_in_dart',
    'Raw GraphQL document strings are forbidden in Dart. Put the operation in '
        'a .graphql file and use the generated *Req class from ferry_generator.',
    severity: DiagnosticSeverity.ERROR,
  );

  /// GraphQL operation keyword at document start (after optional whitespace).
  static final _documentLead = RegExp(
    r'^\s*(query|mutation|subscription)\s*(\w+\s*)?[({]',
    multiLine: true,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _CompilationUnitVisitor(this, context);
    registry.addCompilationUnit(this, visitor);
    registry.addMethodInvocation(this, visitor);
  }
}

final class _CompilationUnitVisitor extends SimpleAstVisitor<void> {
  _CompilationUnitVisitor(this.rule, this.context);

  final NoRawGraphqlInDart rule;
  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (_GraphqlStringLint.skipPath(context.definingUnit.file.path)) {
      return;
    }
    node.accept(_GraphqlStringLint(rule, context));
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_GraphqlStringLint.skipPath(context.definingUnit.file.path)) {
      return;
    }
    if (node.methodName.name == 'gql') {
      final first = _GraphqlStringLint.firstPositionalArg(node.argumentList);
      if (first is StringLiteral) {
        final value = _GraphqlStringLint.combinedLiteralText(first);
        if (value.isNotEmpty) {
          rule.reportAtNode(first);
        }
      }
    }
  }
}

final class _GraphqlStringLint extends RecursiveAstVisitor<void> {
  _GraphqlStringLint(this.rule, this.context);

  final NoRawGraphqlInDart rule;
  final RuleContext context;

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    if (!skipBecauseUnderGqlCall(node) &&
        NoRawGraphqlInDart._documentLead.hasMatch(combinedLiteralText(node))) {
      rule.reportAtNode(node);
    }
    super.visitAdjacentStrings(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (insideAdjacentStrings(node)) {
      return;
    }
    if (!skipBecauseUnderGqlCall(node)) {
      final combined = combinedLiteralText(node);
      if (NoRawGraphqlInDart._documentLead.hasMatch(combined)) {
        rule.reportAtNode(node);
      }
    }
    super.visitStringInterpolation(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (insideAdjacentStrings(node)) {
      return;
    }
    if (!skipBecauseUnderGqlCall(node)) {
      final value = node.stringValue;
      if (value != null && NoRawGraphqlInDart._documentLead.hasMatch(value)) {
        rule.reportAtNode(node);
      }
    }
    super.visitSimpleStringLiteral(node);
  }

  static bool skipPath(String path) {
    if (path.contains('packages/tentura_lints/')) {
      return true;
    }
    if (path.contains('packages/client/test/') ||
        path.contains('packages/server/test/')) {
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

  static bool skipBecauseUnderGqlCall(StringLiteral node) {
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

  static bool insideAdjacentStrings(AstNode node) {
    for (var current = node.parent; current != null; current = current.parent) {
      if (current is AdjacentStrings) {
        return true;
      }
    }
    return false;
  }

  static Expression? firstPositionalArg(ArgumentList list) {
    for (final a in list.arguments) {
      if (a is NamedArgument) {
        continue;
      }
      return a.argumentExpression;
    }
    return null;
  }

  static String combinedLiteralText(StringLiteral node) {
    if (node is SimpleStringLiteral) {
      return node.stringValue ?? '';
    }
    if (node is StringInterpolation) {
      final buffer = StringBuffer();
      for (final element in node.elements) {
        if (element is InterpolationString) {
          buffer.write(element.value);
        }
      }
      return buffer.toString();
    }
    if (node is AdjacentStrings) {
      final buffer = StringBuffer();
      for (final part in node.strings) {
        buffer.write(combinedLiteralText(part));
      }
      return buffer.toString();
    }
    return '';
  }
}
