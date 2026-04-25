import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Forbids `Colors.*` and `Color(0x…)` in scoped operational UI (use theme extension tokens / ColorScheme).
final class NoOperationalRawColor extends DartLintRule {
  const NoOperationalRawColor() : super(code: _code);

  static const _code = LintCode(
    name: 'no_operational_raw_color',
    problemMessage:
        'Do not use raw Color(0x…) or Colors.* in operational beacon / my work / '
        'inbox UI. Use ThemeExtension tokens (e.g. context.tt) or ColorScheme roles.',
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

  static bool _inScope(String path) {
    if (!path.contains('packages/client/lib/')) return false;
    if (path.contains('/design_system/')) return false;
    if (path.contains('/test/')) return false;
    return path.contains('features/beacon_view/') ||
        path.contains('features/my_work/') ||
        path.contains('features/inbox/');
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this._reporter, this._code);

  final DiagnosticReporter _reporter;
  final LintCode _code;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // `NamedType.name2` is the supported accessor for the identifier in this analyzer.
    // ignore: deprecated_member_use
    final t = node.constructorName.type.name2.lexeme;
    if (t == 'Color') {
      for (final a in node.argumentList.arguments) {
        if (a is IntegerLiteral) {
          _reporter.atNode(a, _code);
          break;
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'Colors') {
      if (node.identifier.name == 'transparent') {
        super.visitPrefixedIdentifier(node);
        return;
      }
      _reporter.atNode(node, _code);
    }
    super.visitPrefixedIdentifier(node);
  }
}
