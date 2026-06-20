import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Forbids `Colors.*` and `Color(0x…)` in scoped operational UI.
final class NoOperationalRawColor extends AnalysisRule {
  NoOperationalRawColor()
    : super(
        name: 'no_operational_raw_color',
        description:
            'Do not use raw Color(0x…) or Colors.* in operational UI scopes.',
      );

  static const LintCode code = LintCode(
    'no_operational_raw_color',
    'Do not use raw Color(0x…) or Colors.* in operational beacon / my work / '
    'inbox UI. Use ThemeExtension tokens (e.g. context.tt) or ColorScheme roles.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry.addInstanceCreationExpression(this, visitor);
    registry.addPrefixedIdentifier(this, visitor);
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final NoOperationalRawColor rule;
  final RuleContext context;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!_inScope(context.definingUnit.file.path)) {
      return;
    }
    final t = node.constructorName.type.name.lexeme;
    if (t == 'Color') {
      for (final a in node.argumentList.arguments) {
        if (a is IntegerLiteral) {
          rule.reportAtNode(a);
          break;
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (!_inScope(context.definingUnit.file.path)) {
      return;
    }
    if (node.prefix.name == 'Colors') {
      if (node.identifier.name == 'transparent') {
        super.visitPrefixedIdentifier(node);
        return;
      }
      rule.reportAtNode(node);
    }
    super.visitPrefixedIdentifier(node);
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
