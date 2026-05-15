import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/features/coordination_item/ui/widget/item_card.dart';

import '../bloc/beacon_view_state.dart';
import '../bloc/items_tab_cubit.dart';
import '../bloc/items_tab_state.dart';
import 'beacon_definition_body.dart';

class ItemsTab extends StatelessWidget {
  const ItemsTab({
    required this.state,
    super.key,
  });

  final BeaconViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return BlocBuilder<ItemsTabCubit, ItemsTabState>(
      builder: (context, tabState) {
        if (tabState.isLoading) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final openItems = tabState.openItems;
        final closedItems = tabState.closedItems;
        final hasItems = openItems.isNotEmpty || closedItems.isNotEmpty;

        // Parent CustomScrollView owns scrolling; nested ListView caused
        // parentDataDirty semantics asserts on web.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BeaconDefinitionSection(state: state),
              if (!hasItems)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Center(
                    child: Text(
                      l10n.beaconItemsEmptyPlaceholder,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                )
              else ...[
                const SizedBox(height: 8),
                for (final item in openItems)
                  ItemCard(
                    item: item,
                    onResolve: () {
                      final cubit = context.read<ItemsTabCubit>();
                      if (item.kind == CoordinationItemKind.plan &&
                          item.isPlanStep) {
                        unawaited(cubit.resolvePlanStep(item.id));
                      } else if (item.kind == CoordinationItemKind.ask) {
                        unawaited(cubit.resolveAsk(item.id));
                      } else {
                        unawaited(cubit.resolveBlocker(item.id));
                      }
                    },
                    onCancel: () {
                      final cubit = context.read<ItemsTabCubit>();
                      if (item.kind == CoordinationItemKind.ask) {
                        unawaited(cubit.cancelAsk(item.id));
                      } else {
                        unawaited(cubit.cancelBlocker(item.id));
                      }
                    },
                    onAccept: switch (item.kind) {
                      CoordinationItemKind.ask => () => unawaited(
                            context.read<ItemsTabCubit>().acceptAsk(item.id),
                          ),
                      CoordinationItemKind.resolution => () => unawaited(
                            context
                                .read<ItemsTabCubit>()
                                .acceptResolution(item.id),
                          ),
                      _ => null,
                    },
                    onReject: item.kind == CoordinationItemKind.resolution
                        ? () => unawaited(
                              context
                                  .read<ItemsTabCubit>()
                                  .rejectResolution(item.id),
                            )
                        : null,
                  ),
                if (closedItems.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    title: Text(
                      'Closed (${closedItems.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    children: [
                      for (final item in closedItems) ItemCard(item: item),
                    ],
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BeaconDefinitionSection extends StatelessWidget {
  const _BeaconDefinitionSection({required this.state});

  final BeaconViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final beacon = state.beacon;

    return ExpansionTile(
      leading: const Icon(Icons.info_outline),
      title: Text(
        l10n.beaconDefinitionSectionTitle,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: BeaconDefinitionBody(
            key: ValueKey('items-def-${beacon.id}'),
            beacon: beacon,
          ),
        ),
      ],
    );
  }
}
