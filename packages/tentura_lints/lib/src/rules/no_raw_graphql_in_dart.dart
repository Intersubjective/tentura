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
    final visitor = _Visitor(this, context);
    registry.addSimpleStringLiteral(this, visitor);
    registry.addAdjacentStrings(this, visitor);
    registry.addMethodInvocation(this, visitor);
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final NoRawGraphqlInDart rule;
  final RuleContext context;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (_skipPath(context.definingUnit.file.path)) {
      return;
    }
    if (!_skipBecauseUnderGqlCall(node)) {
      final value = node.stringValue;
      if (value != null && NoRawGraphqlInDart._documentLead.hasMatch(value)) {
        rule.reportAtNode(node);
      }
    }
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    if (_skipPath(context.definingUnit.file.path)) {
      return;
    }
    if (!_skipBecauseUnderGqlCall(node)) {
      final value = node.stringValue;
      if (value != null && NoRawGraphqlInDart._documentLead.hasMatch(value)) {
        rule.reportAtNode(node);
      }
    }
    super.visitAdjacentStrings(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_skipPath(context.definingUnit.file.path)) {
      return;
    }
    if (node.methodName.name == 'gql') {
      final first = _firstPositionalArg(node.argumentList);
      if (first is StringLiteral) {
        final value = first.stringValue;
        if (value != null && value.isNotEmpty) {
          rule.reportAtNode(first);
        }
      }
    }
    super.visitMethodInvocation(node);
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
