import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Forbids ad-hoc `TextStyle(…)` in scoped operational UI (use shared text styles / TextTheme).
final class NoOperationalRawTextStyle extends DartLintRule {
  const NoOperationalRawTextStyle() : super(code: _code);

  static const _code = LintCode(
    name: 'no_operational_raw_text_style',
    problemMessage:
        'Do not use raw TextStyle(…) in operational beacon / my work / inbox UI. '
        'Use design-system text styles (TenturaText) or TextTheme from Theme.of(context).',
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    if (!_inScope(resolver.path)) return;
    context.registry.addCompilationUnit((unit) {
      unit.accept(_TextStyleVisitor(reporter, _code));
    });
  }
}

class _TextStyleVisitor extends RecursiveAstVisitor<void> {
  _TextStyleVisitor(this._reporter, this._code);

  final DiagnosticReporter _reporter;
  final LintCode _code;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // `NamedType.name2` is the supported accessor for the identifier in this analyzer.
    // ignore: deprecated_member_use
    final t = node.constructorName.type.name2.lexeme;
    if (t == 'TextStyle') {
      _reporter.atNode(node, _code);
    }
    super.visitInstanceCreationExpression(node);
  }
}

bool _inScope(String path) {
  if (!path.contains('packages/client/lib/')) return false;
  if (path.contains('/design_system/')) return false;
  if (path.contains('/test/')) return false;
  return path.contains('features/beacon_view/') ||
      path.contains('features/my_work/') ||
      path.contains('features/inbox/');
}
