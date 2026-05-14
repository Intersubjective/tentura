import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/graph/data/repository/forwards_graph_repository.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
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
    @QueryParam('committer') this.helpOffererId,
    @QueryParam('committerName') this.helpOffererName,
    super.key,
  });

  /// Beacon id from the route; used only to load forwards data. The graph
  /// cubit is given the viewer's user id as initial focus (not this value).
  final String focus;

  /// When non-null, switches the screen into help-offerer-path mode and
  /// fetches `beaconHelpOffererForwardPath(id: focus, helpOffererId: ...)`.
  final String? helpOffererId;

  /// Optional help offerer display title forwarded by the People tab so the
  /// AppBar title can read e.g. "Forward path to {name}".
  final String? helpOffererName;

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => ScreenCubit(),
          ),
          BlocProvider(
            create: (_) {
              final me = GetIt.I<ProfileCubit>().state.profile;
              return GraphCubit(
                me: me,
                focus: me.id,
                graphSourceRepository: GetIt.I<ForwardsGraphRepository>(),
                forwardsGraphBeaconId: focus,
                helpOffererFocusUserId: helpOffererId,
              );
            },
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
        leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
        title: BlocBuilder<GraphCubit, GraphState>(
          buildWhen: (p, c) => p.status != c.status,
          builder: (_, _) => Text(_titleFor(l10n, cubit.helpOffererViewerRole)),
        ),
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

  String _titleFor(L10n l10n, ForwardsGraphViewerRole? role) {
    if (helpOffererId == null || role == null) {
      return l10n.forwardsGraphView;
    }
    final name = helpOffererName?.trim();
    final hasName = name != null && name.isNotEmpty;
    return switch (role) {
      ForwardsGraphViewerRole.author => hasName
          ? l10n.helpOffererForwardPathTitleAuthor(name)
          : l10n.forwardsGraphView,
      ForwardsGraphViewerRole.involvedOther => hasName
          ? l10n.helpOffererForwardPathTitleViewer(name)
          : l10n.forwardsGraphView,
      ForwardsGraphViewerRole.self => l10n.helpOffererForwardPathTitleSelf,
    };
  }
}
