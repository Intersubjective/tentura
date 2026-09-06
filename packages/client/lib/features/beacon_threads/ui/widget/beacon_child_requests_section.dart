import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_request_card.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_action_button.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/accordion_expansion.dart';

class BeaconChildRequestsSection extends StatelessWidget {
  const BeaconChildRequestsSection({
    required this.beaconState,
    super.key,
  });

  final BeaconViewState beaconState;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);

    return BlocBuilder<BeaconHierarchyCubit, BeaconHierarchyState>(
      buildWhen: (p, c) =>
          p.capabilities != c.capabilities ||
          p.active != c.active ||
          p.finished != c.finished ||
          p.deleted != c.deleted ||
          p.status != c.status ||
          p.capabilitiesError != c.capabilitiesError,
      builder: (context, hierarchyState) {
        if (hierarchyState.capabilitiesError != null &&
            !hierarchyState.hasCapabilities) {
          return _GroupErrorRow(
            onRetry: () => context.read<BeaconHierarchyCubit>().load(),
          );
        }

        if (!hierarchyState.canListChildren) {
          return const SizedBox.shrink();
        }

        final capabilities = hierarchyState.capabilities!;
        final showCreate = capabilities.canCreateChild;
        final hasAnyChild =
            hierarchyState.active.items.isNotEmpty ||
            hierarchyState.finished.items.isNotEmpty ||
            hierarchyState.deleted.items.isNotEmpty;
        final allEmpty =
            !hierarchyState.active.loading &&
            !hierarchyState.finished.loading &&
            !hasAnyChild;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: tt.sectionGap),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.beaconChildRequestsTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (showCreate)
                  BeaconHudActionButton(
                    icon: Icons.add,
                    label: l10n.beaconCreateChildRequest,
                    onPressed: () => context.router.push(
                      BeaconCreateRoute(
                        parentBeaconId: beaconState.beacon.id,
                      ),
                    ),
                  ),
              ],
            ),
            if (!showCreate && !beaconState.beacon.status.allowsCoordination)
              Padding(
                padding: EdgeInsets.only(top: tt.rowGap),
                child: Text(
                  l10n.beaconStatusRowOutcomeClosed,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (allEmpty && showCreate)
              Padding(
                padding: EdgeInsets.only(top: tt.rowGap),
                child: Text(
                  l10n.beaconChildRequestsEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            _ChildGroupSection(
              title: l10n.beaconChildRequestsActiveTitle,
              group: BeaconHierarchyChildGroup.active,
              slice: hierarchyState.active,
            ),
            _ChildGroupSection(
              title: l10n.beaconChildRequestsFinishedTitle,
              group: BeaconHierarchyChildGroup.finished,
              slice: hierarchyState.finished,
            ),
            _DeletedChildGroupSection(slice: hierarchyState.deleted),
          ],
        );
      },
    );
  }
}

class _ChildGroupSection extends StatelessWidget {
  const _ChildGroupSection({
    required this.title,
    required this.group,
    required this.slice,
  });

  final String title;
  final BeaconHierarchyChildGroup group;
  final BeaconHierarchyGroupSlice slice;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    if (slice.loading && slice.items.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: tt.rowGap),
        child: const Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (slice.error != null && slice.items.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: tt.rowGap),
        child: _GroupErrorRow(
          onRetry: () =>
              context.read<BeaconHierarchyCubit>().refreshGroup(group),
        ),
      );
    }
    if (slice.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(top: tt.rowGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          for (final summary in slice.items)
            Padding(
              padding: EdgeInsets.only(top: tt.cardGap),
              child: BeaconChildRequestCard(summary: summary),
            ),
          if (slice.error != null)
            Padding(
              padding: EdgeInsets.only(top: tt.cardGap),
              child: _GroupErrorRow(
                onRetry: () =>
                    context.read<BeaconHierarchyCubit>().refreshGroup(group),
              ),
            )
          else if (slice.hasMore)
            Padding(
              padding: EdgeInsets.only(top: tt.cardGap),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TenturaTextAction(
                  label: L10n.of(context)!.beaconChildRequestsLoadMore,
                  onPressed: () =>
                      context.read<BeaconHierarchyCubit>().loadMore(group),
                ),
              ),
            )
          else if (slice.loadingMore)
            Padding(
              padding: EdgeInsets.only(top: tt.cardGap),
              child: const Center(
                child: CircularProgressIndicator.adaptive(),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeletedChildGroupSection extends StatelessWidget {
  const _DeletedChildGroupSection({required this.slice});

  final BeaconHierarchyGroupSlice slice;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<BeaconHierarchyCubit>();

    return Padding(
      padding: EdgeInsets.only(top: tt.rowGap),
      child: AccordionExpansionGroup(
        requestedExpandedId:
            slice.expanded ? 'child_requests_deleted' : null,
        child: AccordionExpansionTile(
          id: 'child_requests_deleted',
          initiallyExpanded: false,
          onExpansionChanged: cubit.setDeletedExpanded,
          title: Text(
            l10n.beaconChildRequestsDeletedTitle,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          leading: const Icon(Icons.delete_outline),
          children: [
            if (slice.loading && slice.items.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: tt.tightGap),
                child: const Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (slice.error != null && slice.items.isEmpty)
              _GroupErrorRow(
                onRetry: () => cubit.refreshGroup(
                  BeaconHierarchyChildGroup.deleted,
                ),
              )
            else
              for (final summary in slice.items)
                Padding(
                  padding: EdgeInsets.only(bottom: tt.cardGap),
                  child: BeaconChildRequestCard(summary: summary),
                ),
            if (slice.error != null && slice.items.isNotEmpty)
              _GroupErrorRow(
                onRetry: () => cubit.refreshGroup(
                  BeaconHierarchyChildGroup.deleted,
                ),
              )
            else if (slice.hasMore)
              Align(
                alignment: Alignment.centerLeft,
                child: TenturaTextAction(
                  label: l10n.beaconChildRequestsLoadMore,
                  onPressed: () => cubit.loadMore(
                    BeaconHierarchyChildGroup.deleted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupErrorRow extends StatelessWidget {
  const _GroupErrorRow({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.beaconViewLoadErrorBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        TenturaTextAction(
          label: l10n.myWorkRetry,
          onPressed: onRetry,
        ),
      ],
    );
  }
}
