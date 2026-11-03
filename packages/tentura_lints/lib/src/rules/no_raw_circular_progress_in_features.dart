import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Forbids raw [CircularProgressIndicator] in feature UI.
///
/// Use [TenturaCircularProgress] from the design system (including the
/// first-load gate and inline action progress).
final class NoRawCircularProgressInFeatures extends AnalysisRule {
  NoRawCircularProgressInFeatures()
    : super(
        name: 'no_raw_circular_progress_in_features',
        description:
            'Feature UI must not use CircularProgressIndicator directly.',
      );

  static const LintCode code = LintCode(
    'no_raw_circular_progress_in_features',
    'Do not use CircularProgressIndicator in features/**. '
        'Use TenturaCircularProgress from the design system.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry
      ..addInstanceCreationExpression(this, _Visitor(this, context))
      ..addMethodInvocation(this, _Visitor(this, context));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final NoRawCircularProgressInFeatures rule;
  final RuleContext context;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!_inScope(context.definingUnit.file.path)) {
      return;
    }
    final typeName = node.constructorName.type.name.lexeme;
    if (typeName == 'CircularProgressIndicator') {
      rule.reportAtNode(node);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!_inScope(context.definingUnit.file.path)) {
      return;
    }
    final target = node.target;
    if (target is SimpleIdentifier &&
        target.name == 'CircularProgressIndicator') {
      rule.reportAtNode(node);
    }
    super.visitMethodInvocation(node);
  }
}

bool _inScope(String path) {
  if (!path.contains('packages/client/lib/features/')) {
    return false;
  }
  if (path.contains('/test/')) {
    return false;
  }
  return true;
}
