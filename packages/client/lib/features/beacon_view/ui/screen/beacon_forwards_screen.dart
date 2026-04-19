import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../bloc/beacon_view_cubit.dart';
import '../widget/unified_forward_row.dart';

@RoutePage()
class BeaconForwardsScreen extends StatelessWidget implements AutoRouteWrapper {
  const BeaconForwardsScreen({
    @PathParam('id') this.id = '',
    super.key,
  });

  final String id;

  @override
  Widget wrappedRoute(_) => MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ScreenCubit()),
          BlocProvider(
            create: (_) => BeaconViewCubit(
              myProfile: GetIt.I<ProfileCubit>().state.profile,
              id: id,
            ),
          ),
        ],
        child: MultiBlocListener(
          listeners: const [
            BlocListener<ScreenCubit, ScreenState>(
              listener: commonScreenBlocListener,
            ),
            BlocListener<BeaconViewCubit, BeaconViewState>(
              listener: commonScreenBlocListener,
            ),
          ],
          child: this,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<BeaconViewCubit>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.labelForwards),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: BlocSelector<BeaconViewCubit, BeaconViewState, bool>(
            selector: (state) => state.isLoading,
            builder: LinearPiActive.builder,
            bloc: cubit,
          ),
        ),
      ),
      body: BlocBuilder<BeaconViewCubit, BeaconViewState>(
        bloc: cubit,
        buildWhen: (_, c) => c.isSuccess || c.isLoading || c.hasError,
        builder: (context, state) {
          if (state.isLoading && state.viewerForwardEdges.isEmpty) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }
          final theme = Theme.of(context);
          final edges = state.viewerForwardEdges;
          final hasAny = edges.isNotEmpty;
          final viewerId = state.myProfile.id;

          final feedRows = <Widget>[
            for (final e in edges)
              e.sender.id == viewerId
                  ? UnifiedForwardRow.outgoing(
                      edge: e,
                      viewerUserId: viewerId,
                      committed: state.involvementCommittedIds,
                      watching: state.involvementWatchingIds,
                      onward: state.involvementOnwardForwarderIds,
                    )
                  : UnifiedForwardRow.inbound(
                      sender: e.sender,
                      note: e.note,
                      viewerUserId: viewerId,
                    ),
          ];

          return ListView(
            padding: kPaddingAll,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.send),
                  label: Text(l10n.labelForward),
                  onPressed: () => unawaited(
                    context.router.pushPath('$kPathForwardBeacon/${state.beacon.id}'),
                  ),
                ),
              ),
              const SizedBox(height: kSpacingMedium),
              if (hasAny) ...[
                Padding(
                  padding: kPaddingSmallV,
                  child: Wrap(
                    spacing: kSpacingSmall,
                    runSpacing: kSpacingSmall,
                    children: [
                      BeaconCardPill(
                        label: l10n.beaconForwardsCount(edges.length),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < feedRows.length; i++) ...[
                      if (i > 0) const SizedBox(height: kSpacingMedium),
                      feedRows[i],
                    ],
                  ],
                ),
              ] else
                Padding(
                  padding: kPaddingSmallV,
                  child: Text(
                    l10n.beaconForwardsEmpty,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
