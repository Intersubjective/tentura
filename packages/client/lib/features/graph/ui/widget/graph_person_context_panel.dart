import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/model/person_action_policy.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/availability_line.dart';

import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_request_label.dart';

import '../../domain/entity/node_details.dart';
import '../bloc/graph_person_context_cubit.dart';

/// Trust-graph overlay for the selected person's visibility and actions.
class GraphPersonContextPanel extends StatelessWidget {
  const GraphPersonContextPanel({
    required this.profile,
    required this.focusedNode,
    this.hiddenNeighborCount = 0,
    this.isLoading = false,
    this.canPageMore = false,
    this.onExpand,
    this.discoverableRequests = const [],
    this.requestsExpanded = false,
    this.onToggleRequestsExpanded,
    this.onDiscoverableRequestTap,
    this.footer,
    super.key,
  });

  final Profile profile;
  final UserNode focusedNode;
  final int hiddenNeighborCount;
  final bool isLoading;
  final bool canPageMore;
  final VoidCallback? onExpand;
  final List<ConstellationRequest> discoverableRequests;
  final bool requestsExpanded;
  final VoidCallback? onToggleRequestsExpanded;
  final ValueChanged<ConstellationRequest>? onDiscoverableRequestTap;

  /// Extra action drawn on the same card surface, below the scrollable body.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final scheme = theme.colorScheme;
    final contextCubit = context.read<GraphPersonContextCubit>();
    final contextState = context.watch<GraphPersonContextCubit>().state;
    final todayUtc = availabilityTodayUtc();
    final policy = PersonActionPolicy.from(
      profile,
      isSelf: false,
      isBlocked: false,
      todayUtc: todayUtc,
    );
    final canShowMore = !isLoading && canPageMore && hiddenNeighborCount > 0;

    final body = Column(
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
        if (discoverableRequests.isNotEmpty &&
            onToggleRequestsExpanded != null) ...[
          SizedBox(height: tt.sectionGap),
          _DiscoverableRequestsSection(
            l10n: l10n,
            requests: discoverableRequests,
            expanded: requestsExpanded,
            onToggle: onToggleRequestsExpanded!,
            onRequestTap: onDiscoverableRequestTap,
          ),
        ],
        SizedBox(height: tt.sectionGap),
        ..._buildActions(
          context: context,
          l10n: l10n,
          policy: policy,
          canShowMore: canShowMore,
          hiddenCount: hiddenNeighborCount,
          trustLoading: contextState.trustLoading,
          focusedNode: focusedNode,
          contextCubit: contextCubit,
          onExpand: onExpand,
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
    );

    final Widget paddedBody;
    if (footer == null) {
      paddedBody = SingleChildScrollView(child: body);
    } else {
      paddedBody = LayoutBuilder(
        builder: (context, constraints) {
          final scroll = CustomScrollView(
            shrinkWrap: true,
            slivers: [
              SliverToBoxAdapter(child: body),
            ],
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (constraints.maxHeight.isFinite)
                Flexible(child: scroll)
              else
                scroll,
              SizedBox(height: tt.rowGap),
              footer!,
            ],
          );
        },
      );
    }

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
          child: paddedBody,
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
    required GraphPersonContextCubit contextCubit,
    VoidCallback? onExpand,
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

    if (canShowMore && onExpand != null) {
      addGap();
      children.add(
        FocusTraversalOrder(
          order: const NumericFocusOrder(4),
          child: OutlinedButton.icon(
            key: TestIds.key(TestIds.graphPersonContextShowMore),
            onPressed: onExpand,
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
      // issue-146: bond not shown here yet; the panel never passes
      // sharesActiveContext, so this state is unreachable.
      PersonVisibilityState.neither ||
      PersonVisibilityState.sharedContext => [l10n.profileVisibilityNeither],
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

class _DiscoverableRequestsSection extends StatelessWidget {
  const _DiscoverableRequestsSection({
    required this.l10n,
    required this.requests,
    required this.expanded,
    required this.onToggle,
    this.onRequestTap,
  });

  final L10n l10n;
  final List<ConstellationRequest> requests;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<ConstellationRequest>? onRequestTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TenturaTypeLabel(l10n.constellationPersonActiveRequests),
        SizedBox(height: tt.tightGap),
        OutlinedButton.icon(
          key: const Key('constellation.person_expand'),
          onPressed: onToggle,
          icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          label: Text(
            expanded
                ? l10n.constellationPersonHideRequests
                : l10n.constellationPersonShowRequests(requests.length),
          ),
        ),
        if (expanded) ...[
          SizedBox(height: tt.rowGap),
          for (final request in requests) ...[
            _DiscoverableRequestRow(
              request: request,
              onTap: onRequestTap == null ? null : () => onRequestTap!(request),
            ),
            SizedBox(height: tt.tightGap),
          ],
        ],
      ],
    );
  }
}

class _DiscoverableRequestRow extends StatelessWidget {
  const _DiscoverableRequestRow({
    required this.request,
    this.onTap,
  });

  final ConstellationRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final annotation = constellationHeldAnnotation(l10n, request);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        child: Padding(
          padding: tt.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                constellationRequestLabelText(l10n, request),
                style: theme.textTheme.bodyMedium,
              ),
              if (annotation != null) ...[
                SizedBox(height: tt.tightGap),
                TenturaStatusText(
                  annotation,
                  tone: TenturaTone.info,
                  maxLines: 2,
                  softWrap: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
