import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Whether the library under analysis lives at [pathFragment] in its file path.
bool filePathContains(RuleContext context, String pathFragment) {
  return context.definingUnit.file.path.contains(pathFragment);
}

/// Unwraps optional/default formal parameters to the inner parameter node.
///
/// Analyzer 13+ represents defaults via [FormalParameter.defaultClause] on the
/// parameter itself (no wrapper [DefaultFormalParameter] node), so this is an
/// identity for the current AST.
FormalParameter unwrapFormalParameter(FormalParameter parameter) => parameter;
