import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Forbids `EdgeInsets`/`EdgeInsetsDirectional` built from raw numeric
/// literals in client feature / shared UI.
///
/// Use spacing tokens instead: `context.tt` density tokens (e.g.
/// `EdgeInsets.all(context.tt.cardPadding)`) or `TenturaSpacing.*`. Token-derived
/// insets and `EdgeInsets.zero` are allowed.
final class NoRawEdgeInsets extends AnalysisRule {
  NoRawEdgeInsets()
    : super(
        name: 'no_raw_edge_insets',
        description:
            'Do not build EdgeInsets from raw numeric literals in feature / '
            'shared UI. Use spacing tokens (context.tt / TenturaSpacing).',
      );

  static const LintCode code = LintCode(
    'no_raw_edge_insets',
    'Do not build EdgeInsets from raw numbers in client feature / shared UI. '
    'Use spacing tokens (context.tt density tokens or TenturaSpacing.*); '
    'EdgeInsets.zero and token-derived insets are fine.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    // Unnamed (resolved `EdgeInsets(...)`) and named (`EdgeInsets.all(8)`,
    // commonly parsed as a method invocation) constructor forms.
    registry.addInstanceCreationExpression(this, visitor);
    registry.addMethodInvocation(this, visitor);
  }
}

const _targets = {'EdgeInsets', 'EdgeInsetsDirectional'};

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final NoRawEdgeInsets rule;
  final RuleContext context;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_inScope(context.definingUnit.file.path) &&
        _targets.contains(node.constructorName.type.name.lexeme)) {
      _reportFirstNumericArg(node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (_inScope(context.definingUnit.file.path) &&
        target is SimpleIdentifier &&
        _targets.contains(target.name)) {
      _reportFirstNumericArg(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  void _reportFirstNumericArg(ArgumentList argumentList) {
    for (final argument in argumentList.arguments) {
      final value = argument is NamedExpression
          ? argument.expression
          : argument;
      if (value is IntegerLiteral || value is DoubleLiteral) {
        rule.reportAtNode(value);
        break;
      }
    }
  }
}

bool _inScope(String path) {
  if (!path.contains('packages/client/lib/')) {
    return false;
  }
  if (path.contains('/design_system/')) {
    return false;
  }
  if (path.contains('packages/client/test/')) {
    return false;
  }
  return path.contains('/features/') || path.contains('/ui/');
}
