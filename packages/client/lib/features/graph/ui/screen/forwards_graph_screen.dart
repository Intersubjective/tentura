import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/features/graph/data/repository/forwards_graph_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/graph_cubit.dart';
import '../widget/graph_body.dart';

@RoutePage()
class ForwardsGraphScreen extends StatelessWidget implements AutoRouteWrapper {
  const ForwardsGraphScreen({
    @PathParam('id') this.focus = '',
    super.key,
  });

  /// Beacon id; graph centers on this beacon as focus.
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
              graphSourceRepository: GetIt.I<ForwardsGraphRepository>(),
              forwardsGraphBeaconId: focus,
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
        title: Text(l10n.forwardsGraphView),
        actions: [
          PopupMenuButton<void>(
            itemBuilder: (_) => <PopupMenuEntry<void>>[
              PopupMenuItem<void>(
                onTap: cubit.jumpToEgo,
                child: Text(l10n.goToEgo),
              ),
            ],
          ),
        ],
      ),
      body: const GraphBody(),
    );
  }
}
