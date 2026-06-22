import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Forbids `BorderRadius` / `Radius` built from raw numeric literals in client
/// feature / shared UI.
///
/// Use radius tokens instead: `context.tt.cardRadius` / `context.tt.buttonRadius`
/// or `TenturaRadii.*`. This flags both `BorderRadius.circular(12)` and the
/// nested `Radius.circular(12)` form.
final class NoRawBorderRadius extends AnalysisRule {
  NoRawBorderRadius()
    : super(
        name: 'no_raw_border_radius',
        description:
            'Do not build BorderRadius/Radius from raw numeric literals in '
            'feature / shared UI. Use radius tokens (context.tt / TenturaRadii).',
      );

  static const LintCode code = LintCode(
    'no_raw_border_radius',
    'Do not build BorderRadius/Radius from raw numbers in client feature / '
    'shared UI. Use radius tokens (context.tt.cardRadius / buttonRadius or '
    'TenturaRadii.*).',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    // Named constructor forms (`BorderRadius.circular(8)`, `Radius.circular(8)`)
    // are commonly parsed as method invocations; cover both shapes.
    registry.addInstanceCreationExpression(this, visitor);
    registry.addMethodInvocation(this, visitor);
  }
}

const _targets = {'BorderRadius', 'BorderRadiusDirectional', 'Radius'};

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final NoRawBorderRadius rule;
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
