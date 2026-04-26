import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Forbids numeric literal `fontSize` on `TextStyle` in operational UI — use
/// `TextTheme` / design-system styles instead.
///
/// Allow-listed: `design_system/`, `rating_scatter_view.dart`, `colors_drawer.dart`.
final class NoInlineFontSize extends DartLintRule {
  const NoInlineFontSize() : super(code: _code);

  static const _code = LintCode(
    name: 'no_inline_font_size',
    problemMessage:
        'Do not pass a numeric literal as TextStyle.fontSize in features/ui. '
        'Use Theme.of(context).textTheme, TenturaText, or other design-system styles.',
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    if (!_inScope(resolver.path)) return;
    context.registry.addCompilationUnit((unit) {
      unit.accept(_Visitor(reporter, _code));
    });
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this._reporter, this._code);

  final DiagnosticReporter _reporter;
  final LintCode _code;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // `NamedType.name2` is the supported accessor for the type name (analyzer API).
    // ignore: deprecated_member_use
    final typeName = node.constructorName.type.name2.lexeme;
    if (typeName == 'TextStyle') {
      for (final arg in node.argumentList.arguments) {
        if (arg is! NamedExpression) continue;
        if (arg.name.label.name != 'fontSize') continue;
        final e = arg.expression;
        if (e is IntegerLiteral || e is DoubleLiteral) {
          _reporter.atNode(arg, _code);
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}

bool _inScope(String path) {
  if (!path.contains('packages/client/lib/')) return false;
  if (path.contains('/test/')) return false;
  if (_isAllowListed(path)) return false;
  return path.contains('/features/') || path.contains('/ui/');
}

bool _isAllowListed(String path) {
  if (path.contains('/design_system/')) return true;
  if (path.endsWith('rating_scatter_view.dart')) return true;
  if (path.endsWith('colors_drawer.dart')) return true;
  return false;
}
