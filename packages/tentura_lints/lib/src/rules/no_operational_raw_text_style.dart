import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Forbids ad-hoc `TextStyle(…)` in scoped operational UI.
final class NoOperationalRawTextStyle extends AnalysisRule {
  NoOperationalRawTextStyle()
    : super(
        name: 'no_operational_raw_text_style',
        description:
            'Do not use raw TextStyle(…) in operational beacon / my work / inbox UI.',
      );

  static const LintCode code = LintCode(
    'no_operational_raw_text_style',
    'Do not use raw TextStyle(…) in operational beacon / my work / inbox UI. '
    'Use design-system text styles (TenturaText) or TextTheme from Theme.of(context).',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addInstanceCreationExpression(this, _Visitor(this, context));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final NoOperationalRawTextStyle rule;
  final RuleContext context;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!_inScope(context.definingUnit.file.path)) {
      return;
    }
    final t = node.constructorName.type.name.lexeme;
    if (t == 'TextStyle') {
      rule.reportAtNode(node);
    }
    super.visitInstanceCreationExpression(node);
  }
}

bool _inScope(String path) {
  if (!path.contains('packages/client/lib/')) {
    return false;
  }
  if (path.contains('/design_system/')) {
    return false;
  }
  if (path.contains('/test/')) {
    return false;
  }
  return path.contains('features/beacon_view/') ||
      path.contains('features/my_work/') ||
      path.contains('features/inbox/');
}
