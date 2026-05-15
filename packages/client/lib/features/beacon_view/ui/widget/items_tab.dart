import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/features/coordination_item/ui/widget/item_card.dart';

import '../bloc/items_tab_cubit.dart';
import '../bloc/items_tab_state.dart';

class ItemsTab extends StatelessWidget {
  const ItemsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return BlocBuilder<ItemsTabCubit, ItemsTabState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final openItems = state.openItems;
        final closedItems = state.closedItems;

        if (openItems.isEmpty && closedItems.isEmpty) {
          return Center(
            child: Text(
              l10n.beaconItemsEmptyPlaceholder,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            for (final item in openItems)
              ItemCard(
                item: item,
                onResolve: () {
                  final cubit = context.read<ItemsTabCubit>();
                  if (item.kind == CoordinationItemKind.plan && item.isPlanStep) {
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
                onAccept: item.kind == CoordinationItemKind.ask
                    ? () => unawaited(
                          context.read<ItemsTabCubit>().acceptAsk(item.id),
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
        );
      },
    );
  }
}
