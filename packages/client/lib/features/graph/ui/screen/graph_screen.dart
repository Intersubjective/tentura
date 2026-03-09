import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
// import 'package:tentura/features/context/ui/widget/context_drop_down.dart';

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
        create: (_) => ScreenCubit(),
      ),
      BlocProvider(
        create: (_) => GraphCubit(
          me: GetIt.I<ProfileCubit>().state.profile,
          focus: focus,
        ),
      ),
    ],
    child: MultiBlocListener(
      listeners: const [
        BlocListener<GraphCubit, GraphState>(
          listener: commonScreenBlocListener,
        ),
        BlocListener<ScreenCubit, ScreenState>(
          listener: commonScreenBlocListener,
        ),
      ],
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<GraphCubit>();
    return Scaffold(
      appBar: AppBar(
        leading: const AutoLeadingButton(),

        // Title
        title: Text(l10n.graphView),

        // Menu :
        actions: [
          PopupMenuButton(
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
                child: cubit.state.positiveOnly
                    ? Text(l10n.showNegative)
                    : Text(l10n.hideNegative),
              ),
            ],
          ),
        ],

        // Context selector
        // (hidden for now)
        // bottom: PreferredSize(
        //   preferredSize: const Size.fromHeight(40),
        //   child: Padding(
        //     padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
        //     child: ContextDropDown(onChanged: cubit.setContext),
        //   ),
        // ),
      ),

      // Graph
      body: const GraphBody(),
    );
  }
}
