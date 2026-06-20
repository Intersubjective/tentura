import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../rule_helpers.dart';

/// Domain code must not import the data or UI layers.
final class NoDomainToDataImports extends AnalysisRule {
  NoDomainToDataImports()
    : super(
        name: 'no_domain_to_data_or_ui_import',
        description:
            'Domain must not import data/ or ui/ (use ports and keep layers separate).',
      );

  static const LintCode code = LintCode(
    'no_domain_to_data_or_ui_import',
    'Domain must not import data/ or ui/ (use ports and keep layers separate).',
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

  final NoDomainToDataImports rule;
  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (!filePathContains(context, '/lib/domain/')) {
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
      if (uri.contains('/data/') || uri.contains('/ui/')) {
        rule.reportAtNode(d);
      }
    }
  }
}
