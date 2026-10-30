import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/graph/data/repository/forwards_graph_repository.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/graph_cubit.dart';
import '../../domain/entity/graph_edge_colors.dart';
import '../widget/graph_scaffold.dart';

@RoutePage()
class ForwardsGraphScreen extends StatelessWidget implements AutoRouteWrapper {
  const ForwardsGraphScreen({
    @PathParam('id') this.focus = '',
    @QueryParam('committer') this.helpOffererId,
    @QueryParam('committerName') this.helpOffererName,
    @QueryParam('kind') this.kind,
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

  /// Beacon kind's name passed by the caller (`post`), so a Post is named a
  /// post before the beacon loads (#501). The loaded beacon wins once read.
  final String? kind;

  @override
  Widget wrappedRoute(BuildContext context) => localScreenCubitScope(
    child: BlocProvider(
      create: (context) {
        final me = GetIt.I<ProfileCubit>().state.profile;
        return GraphCubit(
          me: me,
          focus: me.id,
          graphSourceRepository: GetIt.I<ForwardsGraphRepository>(),
          forwardsGraphBeaconId: focus,
          helpOffererFocusUserId: helpOffererId,
          edgeColors: GraphEdgeColors.fromTokens(context.ttOnce),
        );
      },
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final routeKind = BeaconKind.values.asNameMap()[kind?.trim()];
    return GraphScaffold(
      // The legend goes by the route's kind too until the beacon loads.
      beaconKindHint: routeKind,
      leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
      title: BlocBuilder<GraphCubit, GraphState>(
        buildWhen: (p, c) =>
            p.status != c.status ||
            p.helpOffererViewerRole != c.helpOffererViewerRole,
        builder: (context, state) => FutureBuilder<Beacon?>(
          future: context.read<GraphCubit>().forwardsBeacon,
          builder: (context, snapshot) {
            final beacon = snapshot.data;
            // Neither the route nor the beacon says yet whether this is a
            // Post or a Request: no title until it is known, rather than
            // "request" flipping to "post" (#611, #501). An unreadable beacon
            // falls back to the Request wording.
            final routeKind = kind?.trim() ?? '';
            if (beacon == null &&
                routeKind.isEmpty &&
                snapshot.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            // A heading for screen readers (#601), its own node so the
            // beacon title under it is read as plain text.
            final title = Semantics(
              header: true,
              container: true,
              child: Text(
                _titleFor(
                  l10n,
                  state.helpOffererViewerRole,
                  isPost: beacon != null
                      ? beacon.kind == BeaconKind.post
                      : kind == BeaconKind.post.name,
                ),
                // The app bar's text style says one line with ellipsis.
                softWrap: true,
                overflow: TextOverflow.clip,
              ),
            );
            final beaconTitle = beacon?.title.trim();
            if (beaconTitle == null || beaconTitle.isEmpty) {
              return _fitToBar(title);
            }
            // A deep link or a return visit otherwise shows forwards of an
            // unnamed Request or Post.
            return _fitToBar(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  title,
                  Text(
                    beaconTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.bodySmall(context.tt.textMuted),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      progress: BlocSelector<GraphCubit, GraphState, bool>(
        selector: (state) => state.isLoading,
        builder: TenturaTopBar.loadingBar,
      ),
    );
  }

  /// On a narrow phone the heading wraps instead of cutting off the word
  /// that says what spread (#615): laid out at the bar's width, then scaled
  /// down only if the lines are taller than the bar.
  static Widget _fitToBar(Widget child) => LayoutBuilder(
    builder: (context, constraints) => constraints.hasBoundedWidth
        ? FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(width: constraints.maxWidth, child: child),
          )
        : child,
  );

  String _titleFor(
    L10n l10n,
    ForwardsGraphViewerRole? role, {
    required bool isPost,
  }) {
    if (helpOffererId == null || role == null) {
      return isPost ? l10n.forwardsGraphViewPost : l10n.forwardsGraphView;
    }
    final name = helpOffererName?.trim();
    final hasName = name != null && name.isNotEmpty;
    return switch (role) {
      ForwardsGraphViewerRole.author =>
        hasName
            ? l10n.helpOffererForwardPathTitleAuthor(name)
            : l10n.forwardsGraphView,
      ForwardsGraphViewerRole.involvedOther =>
        hasName
            ? l10n.helpOffererForwardPathTitleViewer(name)
            : l10n.forwardsGraphView,
      ForwardsGraphViewerRole.self => l10n.helpOffererForwardPathTitleSelf,
    };
  }
}
