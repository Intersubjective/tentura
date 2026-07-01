import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/ui/widget/graph_body.dart';
import 'package:tentura/features/invite_genealogy/data/repository/invite_genealogy_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

@RoutePage()
class InviteGenealogyScreen extends StatelessWidget
    implements AutoRouteWrapper {
  const InviteGenealogyScreen({
    @QueryParam(kQueryGenealogyWith) this.targetId,
    super.key,
  });

  /// When non-null, shows the pairwise lineage between the viewer and this user.
  final String? targetId;

  @override
  Widget wrappedRoute(BuildContext context) {
    final l10n = L10n.of(context)!;
    return localScreenCubitScope(
      child: BlocProvider(
        create: (context) => GraphCubit(
          me: GetIt.I<ProfileCubit>().state.profile,
          graphSourceRepository: GetIt.I<InviteGenealogyRepository>(),
          genealogyMode: true,
          genealogyTargetId: (targetId?.isEmpty ?? true) ? null : targetId,
          genealogyAnonymousNodeLabel: l10n.inviteGenealogyAnonymousNode,
          edgeColors: GraphEdgeColors.fromTokens(context.ttOnce),
        ),
        child: this,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final isBetween = !(targetId?.isEmpty ?? true);
    return Scaffold(
      appBar: AppBar(
        leading: const AutoLeadingWithFallback(fallbackPath: kPathProfile),
        title: Text(
          isBetween
              ? l10n.inviteGenealogyBetweenTitle
              : l10n.showInviteGenealogy,
        ),
        bottom: PreferredSize(
          preferredSize: LinearPiActive.size,
          child: BlocBuilder<GraphCubit, GraphState>(
            buildWhen: (previous, current) =>
                previous.isLoading != current.isLoading,
            builder: (context, state) =>
                LinearPiActive.builder(context, state.isLoading),
          ),
        ),
      ),
      body: const TenturaFullBleed(child: GraphBody()),
    );
  }
}
