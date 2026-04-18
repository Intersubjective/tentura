import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_forward_provenance_panel.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../bloc/beacon_view_cubit.dart';
import '../widget/self_aware_plain_mini_avatar.dart';

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
          if (state.isLoading &&
              state.forwardProvenance.senders.isEmpty &&
              state.myForwards.isEmpty) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }
          final theme = Theme.of(context);
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
              Padding(
                padding: kPaddingSmallV,
                child: Wrap(
                  spacing: kSpacingSmall,
                  runSpacing: kSpacingSmall,
                  children: [
                    BeaconCardPill(
                      label: l10n.beaconForwardsCount(
                        state.forwardProvenance.totalDistinctSenders,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.forwardProvenance.senders.isEmpty)
                Padding(
                  padding: kPaddingSmallV,
                  child: Text(
                    l10n.beaconForwardsEmpty,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                InboxForwardProvenancePanel(
                  provenance: state.forwardProvenance,
                  latestNotePreview: state.inboxLatestNotePreview,
                  recipient: state.myProfile,
                ),
              if (state.myForwards.isNotEmpty) ...[
                const SizedBox(height: kSpacingMedium),
                _MyForwardsSection(
                  edges: state.myForwards,
                  involvementCommittedIds: state.involvementCommittedIds,
                  involvementWatchingIds: state.involvementWatchingIds,
                  involvementOnwardForwarderIds:
                      state.involvementOnwardForwarderIds,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MyForwardsSection extends StatelessWidget {
  const _MyForwardsSection({
    required this.edges,
    required this.involvementCommittedIds,
    required this.involvementWatchingIds,
    required this.involvementOnwardForwarderIds,
  });

  final List<ForwardEdge> edges;
  final Set<String> involvementCommittedIds;
  final Set<String> involvementWatchingIds;
  final Set<String> involvementOnwardForwarderIds;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.myForwardsSectionLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: kSpacingSmall),
        for (final edge in edges)
          Padding(
            padding: const EdgeInsets.only(bottom: kSpacingSmall),
            child: _MyForwardTile(
              edge: edge,
              involvementCommittedIds: involvementCommittedIds,
              involvementWatchingIds: involvementWatchingIds,
              involvementOnwardForwarderIds: involvementOnwardForwarderIds,
            ),
          ),
      ],
    );
  }
}

class _MyForwardTile extends StatelessWidget {
  const _MyForwardTile({
    required this.edge,
    required this.involvementCommittedIds,
    required this.involvementWatchingIds,
    required this.involvementOnwardForwarderIds,
  });

  final ForwardEdge edge;
  final Set<String> involvementCommittedIds;
  final Set<String> involvementWatchingIds;
  final Set<String> involvementOnwardForwarderIds;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sender = edge.sender;
    final recipient = edge.recipient;
    final isDeclined = edge.recipientRejected;
    final recipientOverlay = _myForwardRecipientOverlayIcon(
      edge: edge,
      involvementCommittedIds: involvementCommittedIds,
      involvementWatchingIds: involvementWatchingIds,
      involvementOnwardForwarderIds: involvementOnwardForwarderIds,
      scheme: scheme,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: kPaddingAllS,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlocBuilder<ProfileCubit, ProfileState>(
              buildWhen: (p, c) => p.profile.id != c.profile.id,
              builder: (context, state) {
                final baseName = theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                );
                return Row(
                  children: [
                    SelfAwarePlainMiniAvatar(
                      profile: sender,
                      size: 32,
                    ),
                    const SizedBox(width: kSpacingSmall),
                    Flexible(
                      child: Text(
                        SelfUserHighlight.displayName(
                          l10n,
                          sender,
                          state.profile.id,
                        ),
                        style: SelfUserHighlight.nameStyle(
                          theme,
                          baseName,
                          SelfUserHighlight.profileIsSelf(
                            sender,
                            state.profile.id,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          SelfAwarePlainMiniAvatar(
                            profile: recipient,
                            size: 32,
                            overlay: recipientOverlay,
                          ),
                          const SizedBox(width: kSpacingSmall),
                          Expanded(
                            child: Text(
                              SelfUserHighlight.displayName(
                                l10n,
                                recipient,
                                state.profile.id,
                              ),
                              style: SelfUserHighlight.nameStyle(
                                theme,
                                baseName,
                                SelfUserHighlight.profileIsSelf(
                                  recipient,
                                  state.profile.id,
                                ),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            if (edge.note.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '"${edge.note}"',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (isDeclined) ...[
              const SizedBox(height: 4),
              Text(
                edge.recipientRejectionMessage.isNotEmpty
                    ? l10n.myForwardDeclinedWithReason(
                        edge.recipientRejectionMessage,
                      )
                    : l10n.myForwardDeclined,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.error,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Recipient overlay: rejected > committed > onwardForwarder > watching.
Widget? _myForwardRecipientOverlayIcon({
  required ForwardEdge edge,
  required Set<String> involvementCommittedIds,
  required Set<String> involvementWatchingIds,
  required Set<String> involvementOnwardForwarderIds,
  required ColorScheme scheme,
}) {
  final id = edge.recipient.id;

  if (edge.recipientRejected) {
    return Icon(Icons.block, size: 16, color: scheme.error);
  }
  if (involvementCommittedIds.contains(id)) {
    return Icon(Icons.check_circle_outline, size: 16, color: scheme.tertiary);
  }
  if (involvementOnwardForwarderIds.contains(id)) {
    return Icon(
      Icons.forward_to_inbox,
      size: 16,
      color: scheme.onSurfaceVariant,
    );
  }
  if (involvementWatchingIds.contains(id)) {
    return Icon(
      Icons.visibility_outlined,
      size: 16,
      color: scheme.onSurfaceVariant,
    );
  }
  return null;
}
