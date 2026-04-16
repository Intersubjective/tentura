import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

PluginBase createPlugin() => _TenturaLintsPlugin();

final class _TenturaLintsPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
    const _NoDomainToDataImports(),
    const _NoCubitToDataServiceImports(),
  ];
}

/// Domain code must not import the data or UI layers.
final class _NoDomainToDataImports extends DartLintRule {
  const _NoDomainToDataImports() : super(code: _domainToDataCode);

  static const _domainToDataCode = LintCode(
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
          reporter.atNode(d, _domainToDataCode);
        }
      }
    });
  }
}

/// Cubits must not depend on data services directly (use repositories / use cases).
final class _NoCubitToDataServiceImports extends DartLintRule {
  const _NoCubitToDataServiceImports() : super(code: _cubitToServiceCode);

  static const _cubitToServiceCode = LintCode(
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
          reporter.atNode(d, _cubitToServiceCode);
        }
      }
    });
  }
}
