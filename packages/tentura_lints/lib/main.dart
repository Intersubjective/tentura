import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/rules/cubit_requires_use_case_for_multi_repos.dart';
import 'src/rules/no_cubit_to_data_service_imports.dart';
import 'src/rules/no_domain_to_data_imports.dart';
import 'src/rules/no_inline_font_size.dart';
import 'src/rules/no_map_dynamic_in_use_case_api.dart';
import 'src/rules/no_operational_pill_widgets.dart';
import 'src/rules/no_operational_raw_color.dart';
import 'src/rules/no_operational_raw_text_style.dart';
import 'src/rules/no_raw_border_radius.dart';
import 'src/rules/no_raw_edge_insets.dart';
import 'src/rules/no_raw_graphql_in_dart.dart';
import 'src/rules/no_request_domain_entity.dart';

final plugin = TenturaLintsPlugin();

class TenturaLintsPlugin extends Plugin {
  @override
  String get name => 'tentura_lints';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerLintRule(NoDomainToDataImports())
      ..registerLintRule(NoCubitToDataServiceImports())
      ..registerLintRule(NoMapDynamicInUseCaseApi())
      ..registerLintRule(NoRawGraphqlInDart())
      ..registerLintRule(NoInlineFontSize())
      ..registerLintRule(CubitRequiresUseCaseForMultiRepos())
      ..registerLintRule(NoOperationalRawColor())
      ..registerLintRule(NoOperationalRawTextStyle())
      ..registerLintRule(NoOperationalPillWidgetsInBeaconView())
      ..registerLintRule(NoRawEdgeInsets())
      ..registerLintRule(NoRawBorderRadius())
      ..registerLintRule(NoRequestDomainEntity());
  }
}
