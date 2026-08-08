import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';

import '../bloc/graph_cubit.dart';
import '../bloc/graph_person_context_cubit.dart';
import '../../domain/entity/graph_edge_colors.dart';
import '../widget/graph_scaffold.dart';

@RoutePage()
class GraphScreen extends StatelessWidget implements AutoRouteWrapper {
  const GraphScreen({
    @PathParam('id') this.focus = '',
    super.key,
  });

  final String focus;

  @override
  Widget wrappedRoute(BuildContext context) => localScreenCubitScope(
    child: BlocProvider(
      create: (context) => GraphCubit(
        me: GetIt.I<ProfileCubit>().state.profile,
        focus: focus,
        edgeColors: GraphEdgeColors.fromTokens(context.ttOnce),
      ),
      child: BlocProvider(
        create: (context) => GraphPersonContextCubit(
          profileViewCase: GetIt.I<ProfileViewCase>(),
          graphCubit: context.read<GraphCubit>(),
        ),
        child: this,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return GraphScaffold(
      personContextEnabled: true,
      leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
      title: Text(l10n.graphView),
    );
  }
}
