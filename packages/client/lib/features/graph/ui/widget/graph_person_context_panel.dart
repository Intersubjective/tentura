import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/sheet/availability_sheet.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/model/person_action_policy.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/availability_line.dart';

import '../../domain/entity/node_details.dart';
import '../bloc/graph_cubit.dart';
import '../bloc/graph_person_context_cubit.dart';

/// Trust-graph overlay for the selected person's visibility and actions.
class GraphPersonContextPanel extends StatelessWidget {
  const GraphPersonContextPanel({
    required this.profile,
    required this.focusedNode,
    required this.graphState,
    super.key,
  });

  final Profile profile;
  final UserNode focusedNode;
  final GraphState graphState;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final scheme = theme.colorScheme;
    final graphCubit = context.read<GraphCubit>();
    final contextCubit = context.read<GraphPersonContextCubit>();
    final contextState = context.watch<GraphPersonContextCubit>().state;
    final todayUtc = availabilityTodayUtc();
    final policy = PersonActionPolicy.from(
      profile,
      isSelf: false,
      isBlocked: false,
      todayUtc: todayUtc,
    );
    final hiddenCount = graphState.hiddenNeighborCounts[focusedNode.id] ?? 0;
    final canShowMore =
        !graphState.isLoading &&
        graphCubit.canPageMore(focusedNode.id) &&
        hiddenCount > 0;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Material(
        key: TestIds.key(TestIds.graphPersonContextPanel),
        color: scheme.surfaceContainerHigh,
        elevation: 4,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: tt.cardPadding,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TenturaAvatar(
                      profile: profile,
                      sizeBucket: TenturaAvatarSize.medium,
                      withContactBadge: true,
                    ),
                    SizedBox(width: tt.avatarTextGap),
                    Expanded(
                      child: Text(
                        profile.displayLabel(l10n.unknownPerson),
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(5),
                      child: IconButton(
                        key: TestIds.key(TestIds.graphPersonContextClose),
                        tooltip: l10n.buttonClose,
                        onPressed: contextCubit.dismiss,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: tt.rowGap),
                _OtherProfileAvailabilityLine(
                  profile: profile,
                  todayUtc: todayUtc,
                ),
                _VisibilitySection(
                  l10n: l10n,
                  profile: profile,
                  policy: policy,
                ),
                SizedBox(height: tt.sectionGap),
                ..._buildActions(
                  context: context,
                  l10n: l10n,
                  policy: policy,
                  canShowMore: canShowMore,
                  hiddenCount: hiddenCount,
                  trustLoading: contextState.trustLoading,
                  focusedNode: focusedNode,
                  graphCubit: graphCubit,
                  contextCubit: contextCubit,
                ),
                if (contextState.trustError != null) ...[
                  SizedBox(height: tt.rowGap),
                  Text(
                    contextState.trustError.toString(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions({
    required BuildContext context,
    required L10n l10n,
    required PersonActionPolicy policy,
    required bool canShowMore,
    required int hiddenCount,
    required bool trustLoading,
    required UserNode focusedNode,
    required GraphCubit graphCubit,
    required GraphPersonContextCubit contextCubit,
  }) {
    final screenCubit = context.read<ScreenCubit>();
    final children = <Widget>[];

    void addGap() {
      if (children.isNotEmpty) {
        children.add(SizedBox(height: context.tt.rowGap));
      }
    }

    switch (policy.primaryAction) {
      case PersonPrimaryAction.sendRequest:
        addGap();
        children.add(
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: FilledButton.icon(
              key: TestIds.key(TestIds.graphPersonContextSendRequest),
              onPressed: () => screenCubit.showForwardToPerson(profile.id),
              icon: const Icon(Icons.send_outlined),
              label: Text(l10n.profileSendRequestTo),
            ),
          ),
        );
      case PersonPrimaryAction.trust:
        addGap();
        children.add(
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: FilledButton.icon(
              key: TestIds.key(TestIds.graphPersonContextTrust),
              onPressed: trustLoading ? null : contextCubit.trustSelected,
              icon: const Icon(Icons.people),
              label: Text(l10n.trustThisUser),
            ),
          ),
        );
      case PersonPrimaryAction.none:
        if (policy.showRequestOptions && policy.viewerExplicitlyTrustsSubject) {
          addGap();
          children.add(
            Text(
              l10n.profileRequestUnavailable,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
    }

    if (policy.showRequestOptions) {
      addGap();
      children.add(
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: OutlinedButton.icon(
            key: TestIds.key(TestIds.graphPersonContextRequestOptions),
            onPressed: () => screenCubit.showForwardToPerson(profile.id),
            icon: const Icon(Icons.alt_route_outlined),
            label: Text(l10n.profileRequestOptions),
          ),
        ),
      );
    }

    if (policy.showSecondaryTrust) {
      addGap();
      children.add(
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: OutlinedButton.icon(
            key: TestIds.key(TestIds.graphPersonContextTrust),
            onPressed: trustLoading ? null : contextCubit.trustSelected,
            icon: const Icon(Icons.people_outlined),
            label: Text(l10n.trustThisUser),
          ),
        ),
      );
    }

    addGap();
    children.add(
      FocusTraversalOrder(
        order: const NumericFocusOrder(3),
        child: OutlinedButton.icon(
          key: TestIds.key(TestIds.graphPersonContextViewProfile),
          onPressed: () => screenCubit.showProfile(profile.id),
          icon: const Icon(Icons.person_outline),
          label: Text(l10n.profile),
        ),
      ),
    );

    if (canShowMore) {
      addGap();
      children.add(
        FocusTraversalOrder(
          order: const NumericFocusOrder(4),
          child: OutlinedButton.icon(
            key: TestIds.key(TestIds.graphPersonContextShowMore),
            onPressed: () => graphCubit.expandNode(focusedNode),
            icon: const Icon(Icons.hub_outlined),
            label: Text(l10n.graphShowMoreConnections(hiddenCount)),
          ),
        ),
      );
    }

    return children;
  }
}

class _OtherProfileAvailabilityLine extends StatelessWidget {
  const _OtherProfileAvailabilityLine({
    required this.profile,
    required this.todayUtc,
  });

  final Profile profile;
  final DateTime todayUtc;

  @override
  Widget build(BuildContext context) {
    final line = otherAvailabilityStatusLine(
      L10n.of(context)!,
      profile.availability,
      todayUtc,
    );
    if (line == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: context.tt.rowGap),
      child: TenturaStatusText(
        line,
        tone: TenturaTone.neutral,
        maxLines: null,
        softWrap: true,
      ),
    );
  }
}

class _VisibilitySection extends StatelessWidget {
  const _VisibilitySection({
    required this.l10n,
    required this.profile,
    required this.policy,
  });

  final L10n l10n;
  final Profile profile;
  final PersonActionPolicy policy;

  List<String> _directionalLines() {
    final name = profile.shownName;
    return switch (policy.visibilityState) {
      PersonVisibilityState.mutual => [l10n.profileVisibilityMutual],
      PersonVisibilityState.viewerOnly => [
        l10n.profileVisibilityYouCanSee(name),
        l10n.profileVisibilityCantSeeYou(name),
      ],
      PersonVisibilityState.subjectOnly => [
        l10n.profileVisibilityTheyCanSeeYou(name),
        l10n.profileVisibilityYouDontSeeThem(name),
      ],
      PersonVisibilityState.neither => [l10n.profileVisibilityNeither],
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final eyeOpen = policy.isMutuallyVisible;
    final eyeTooltip = eyeOpen
        ? l10n.graphLegendEyeOpen
        : l10n.graphLegendEyeClosed;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: eyeTooltip,
          child: Icon(
            eyeOpen ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: tt.iconSize,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(width: tt.iconTextGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in _directionalLines())
                Text(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
