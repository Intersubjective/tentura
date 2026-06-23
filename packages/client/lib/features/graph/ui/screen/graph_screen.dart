import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/graph_cubit.dart';
import '../widget/graph_body.dart';

@RoutePage()
class GraphScreen extends StatelessWidget implements AutoRouteWrapper {
  const GraphScreen({
    @PathParam('id') this.focus = '',
    super.key,
  });

  final String focus;

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => ScreenCubit.local(),
      ),
      BlocProvider(
        create: (_) => GraphCubit(
          me: GetIt.I<ProfileCubit>().state.profile,
          focus: focus,
        ),
      ),
    ],
    child: BlocListener<ScreenCubit, ScreenState>(
      // Route-local nested-router navigation only (see UiEffect port plan Phase 6).
      listener: commonScreenBlocListener,
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<GraphCubit>();
    final tt = context.tt;
    return Scaffold(
      appBar: AppBar(
        leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),

        // Title
        title: Text(l10n.graphView),

        // Menu :
        actions: [
          BlocBuilder<GraphCubit, GraphState>(
            buildWhen: (previous, current) =>
                previous.positiveOnly != current.positiveOnly,
            builder: (context, state) => PopupMenuButton<void>(
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
                //
                const PopupMenuDivider(),
                //
                PopupMenuItem<void>(
                  onTap: cubit.togglePositiveOnly,
                  child: state.positiveOnly
                      ? Text(l10n.showNegative)
                      : Text(l10n.hideNegative),
                ),
              ],
            ),
          ),
        ],

      ),

      // Graph
      body: const TenturaFullBleed(child: GraphBody()),
    );
  }
}
