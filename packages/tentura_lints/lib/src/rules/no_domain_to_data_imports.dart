import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Domain code must not import the data or UI layers.
final class NoDomainToDataImports extends DartLintRule {
  const NoDomainToDataImports() : super(code: _code);

  static const _code = LintCode(
    name: 'no_domain_to_data_or_ui_import',
    problemMessage:
        'Domain must not import data/ or ui/ (use ports and keep layers separate).',
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    final path = resolver.path;
    if (!path.contains('/lib/domain/')) return;

    context.registry.addCompilationUnit((unit) {
      for (final d in unit.directives) {
        if (d is! ImportDirective) continue;
        final uri = d.uri.stringValue;
        if (uri == null) continue;
        if (!uri.startsWith('package:tentura/')) continue;
        if (uri.contains('/data/') || uri.contains('/ui/')) {
          reporter.atNode(d, _code);
        }
      }
    });
  }
}
