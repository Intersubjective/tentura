import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Cubits must not depend on data services directly (use repositories / use cases).
final class NoCubitToDataServiceImports extends DartLintRule {
  const NoCubitToDataServiceImports() : super(code: _code);

  static const _code = LintCode(
    name: 'no_cubit_to_data_service_import',
    problemMessage:
        'Cubits must not import data/service (use repositories or use cases).',
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    final path = resolver.path;
    if (!path.contains('/ui/bloc/') || !path.endsWith('_cubit.dart')) return;

    context.registry.addCompilationUnit((unit) {
      for (final d in unit.directives) {
        if (d is! ImportDirective) continue;
        final uri = d.uri.stringValue;
        if (uri == null) continue;
        if (!uri.startsWith('package:tentura/')) continue;
        if (uri.contains('/data/service/')) {
          reporter.atNode(d, _code);
        }
      }
    });
  }
}
