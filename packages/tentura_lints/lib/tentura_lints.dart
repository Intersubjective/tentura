import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'src/rules/cubit_requires_use_case_for_multi_repos.dart';
import 'src/rules/no_cubit_to_data_service_imports.dart';
import 'src/rules/no_domain_to_data_imports.dart';
import 'src/rules/no_map_dynamic_in_use_case_api.dart';
import 'src/rules/no_raw_graphql_in_dart.dart';

PluginBase createPlugin() => _TenturaLintsPlugin();

final class _TenturaLintsPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
    const NoDomainToDataImports(),
    const NoCubitToDataServiceImports(),
    const NoMapDynamicInUseCaseApi(),
    const NoRawGraphqlInDart(),
    const CubitRequiresUseCaseForMultiRepos(),
  ];
}
