import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Cubits must not depend on data services directly (use repositories / use cases).
final class NoCubitToDataServiceImports extends AnalysisRule {
  NoCubitToDataServiceImports()
    : super(
        name: 'no_cubit_to_data_service_import',
        description:
            'Cubits must not import data/service (use repositories or use cases).',
      );

  static const LintCode code = LintCode(
    'no_cubit_to_data_service_import',
    'Cubits must not import data/service (use repositories or use cases).',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addCompilationUnit(this, _Visitor(this, context));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final NoCubitToDataServiceImports rule;
  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final path = context.definingUnit.file.path;
    if (!path.contains('/ui/bloc/') || !path.endsWith('_cubit.dart')) {
      return;
    }
    for (final d in node.directives) {
      if (d is! ImportDirective) {
        continue;
      }
      final uri = d.uri.stringValue;
      if (uri == null) {
        continue;
      }
      if (!uri.startsWith('package:tentura/')) {
        continue;
      }
      if (uri.contains('/data/service/')) {
        rule.reportAtNode(d);
      }
    }
  }
}
