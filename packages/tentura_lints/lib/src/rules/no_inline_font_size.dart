import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Forbids numeric literal `fontSize` on `TextStyle` in operational UI.
final class NoInlineFontSize extends AnalysisRule {
  NoInlineFontSize()
    : super(
        name: 'no_inline_font_size',
        description:
            'Do not pass a numeric literal as TextStyle.fontSize in features/ui.',
      );

  static const LintCode code = LintCode(
    'no_inline_font_size',
    'Do not pass a numeric literal as TextStyle.fontSize in features/ui. '
    'Use Theme.of(context).textTheme, TenturaText, or other design-system styles.',
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

  final NoInlineFontSize rule;
  final RuleContext context;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!_inScope(context.definingUnit.file.path)) {
      return;
    }
    final typeName = node.constructorName.type.name.lexeme;
    if (typeName == 'TextStyle') {
      for (final arg in node.argumentList.arguments) {
        if (arg is! NamedExpression) {
          continue;
        }
        if (arg.name.label.name != 'fontSize') {
          continue;
        }
        final e = arg.expression;
        if (e is IntegerLiteral || e is DoubleLiteral) {
          rule.reportAtNode(arg);
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}

bool _inScope(String path) {
  if (!path.contains('packages/client/lib/')) {
    return false;
  }
  if (path.contains('/test/')) {
    return false;
  }
  if (path.contains('/design_system/')) {
    return false;
  }
  if (path.contains('rating_scatter_view.dart')) {
    return false;
  }
  if (path.contains('colors_drawer.dart')) {
    return false;
  }
  return path.contains('/features/') || path.contains('/ui/');
}
