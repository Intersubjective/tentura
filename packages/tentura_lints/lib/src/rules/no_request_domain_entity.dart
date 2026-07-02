import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../rule_helpers.dart';

/// Blocks parallel Request domain types — user-facing label only; Beacon stays canonical.
final class NoRequestDomainEntity extends AnalysisRule {
  NoRequestDomainEntity()
    : super(
        name: 'no_request_domain_entity',
        description:
            'Do not introduce Request as a domain entity; Beacon is the internal type.',
      );

  static const LintCode code = LintCode(
    'no_request_domain_entity',
    'Do not introduce Request as a domain entity; use Beacon internally '
    'and Request only in user-facing copy.',
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

  final NoRequestDomainEntity rule;
  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (!_inDomainLayer(context)) {
      return;
    }
    for (final decl in node.declarations) {
      if (decl is ClassDeclaration) {
        final name = decl.declaredFragment?.element.name ?? '';
        if (name == 'Request' || name == 'RequestEntity') {
          rule.reportAtNode(decl);
        }
      }
      if (decl is GenericTypeAlias) {
        final name = decl.declaredFragment?.element.name ?? '';
        if (name == 'Request' || name == 'RequestEntity') {
          rule.reportAtNode(decl);
        }
      }
    }
  }
}

bool _inDomainLayer(RuleContext context) {
  final path = context.definingUnit.file.path;
  return path.contains('/lib/domain/') ||
      (path.contains('/features/') && path.contains('/domain/'));
}
