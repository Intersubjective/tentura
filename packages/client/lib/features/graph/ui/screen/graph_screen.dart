import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/graph_cubit.dart';
import '../../domain/entity/graph_edge_colors.dart';
import '../widget/graph_body.dart';

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
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<GraphCubit>();
    final tt = context.tt;
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        alignment: TenturaTopBarAlignment.fullWidth,
        leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
        title: Text(l10n.graphView),
        actions: [
          PopupMenuButton<void>(
            icon: const Icon(Icons.more_vert),
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              minWidth: tt.buttonHeight,
              minHeight: tt.buttonHeight,
            ),
            itemBuilder: (_) => <PopupMenuEntry<void>>[
              PopupMenuItem<void>(
                onTap: cubit.jumpToEgo,
                child: Text(l10n.goToEgo),
              ),
            ],
          ),
        ],
      ),

      // Graph
      body: const TenturaFullBleed(child: GraphBody()),
    );
  }
}
