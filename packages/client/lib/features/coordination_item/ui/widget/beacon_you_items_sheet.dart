import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/ui/coordination_room_navigation.dart';
import 'package:tentura/features/coordination_item/ui/bloc/beacon_you_items_cubit.dart';
import 'package:tentura/features/coordination_item/ui/widget/coordination_item_edit_sheet.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Future<void> showBeaconYouItemsSheet(
  BuildContext context, {
  required String beaconId,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (ctx) => BlocProvider(
      create: (_) => BeaconYouItemsCubit(beaconId: beaconId),
      child: _BeaconYouItemsSheetBody(onChanged: onChanged),
    ),
  );
}

class _BeaconYouItemsSheetBody extends StatelessWidget {
  const _BeaconYouItemsSheetBody({this.onChanged});

  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return BlocConsumer<BeaconYouItemsCubit, BeaconYouItemsState>(
      listenWhen: (prev, next) =>
          prev.status != next.status && next.status is StateIsSuccess,
      listener: (context, state) => onChanged?.call(),
      builder: (context, state) {
        final grouped = _groupByKind(state.items);
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.beaconYouItemsSheetTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (state.status is StateIsLoading && state.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.status is StateHasError && state.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Unable to load items'),
                )
              else if (grouped.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    l10n.beaconYouNoOpenItems,
                    style: TextStyle(color: tt.textMuted),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final entry in grouped.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Text(
                            _kindSectionLabel(l10n, entry.key),
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: tt.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        for (final item in entry.value)
                          _YouItemRow(
                            item: item,
                            onChanged: onChanged,
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

Map<CoordinationItemKind, List<CoordinationItem>> _groupByKind(
  List<CoordinationItem> items,
) {
  final grouped = <CoordinationItemKind, List<CoordinationItem>>{};
  for (final item in groupYouItemsByKind(items)) {
    grouped.putIfAbsent(item.kind, () => []).add(item);
  }
  return grouped;
}

String _kindSectionLabel(L10n l10n, CoordinationItemKind kind) =>
    switch (kind) {
      CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
      CoordinationItemKind.promise => l10n.coordinationPromiseCardLabel,
      CoordinationItemKind.blocker => l10n.coordinationBlockerCardLabel,
      CoordinationItemKind.resolution => l10n.coordinationResolutionCardLabel,
      CoordinationItemKind.plan => l10n.coordinationPlanCardLabel,
    };

class _YouItemRow extends StatelessWidget {
  const _YouItemRow({
    required this.item,
    this.onChanged,
  });

  final CoordinationItem item;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final cubit = context.read<BeaconYouItemsCubit>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.title.trim().isEmpty ? item.body.trim() : item.title.trim(),
            style: theme.textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _actionsForItem(context, l10n, cubit),
          ),
        ],
      ),
    );
  }

  List<Widget> _actionsForItem(
    BuildContext context,
    L10n l10n,
    BeaconYouItemsCubit cubit,
  ) {
    Future<void> run(Future<void> Function() action) async {
      await action();
      onChanged?.call();
    }

    switch (item.kind) {
      case CoordinationItemKind.ask:
        return [
          _actionButton(
            l10n.beaconYouActionReply,
            () => _openItemThread(context, item),
          ),
          _actionButton(
            l10n.beaconYouActionDone,
            () => run(() => cubit.resolveAsk(item.id)),
          ),
          _actionButton(
            l10n.beaconYouActionDecline,
            () => run(() => cubit.cancelAsk(item.id)),
          ),
        ];
      case CoordinationItemKind.promise:
        return [
          _actionButton(
            l10n.beaconYouActionDone,
            () => run(() => cubit.resolvePromise(item.id)),
          ),
          _actionButton(
            l10n.beaconYouActionUpdate,
            () => showCoordinationItemEditSheet(
              context,
              item: item,
              onSaved: onChanged,
            ),
          ),
          _actionButton(
            l10n.beaconYouActionWithdraw,
            () => run(() => cubit.cancelPromise(item.id)),
          ),
        ];
      case CoordinationItemKind.blocker:
        return [
          _actionButton(
            l10n.beaconYouActionResolve,
            () => run(() => cubit.resolveBlocker(item.id)),
          ),
          _actionButton(
            l10n.beaconYouActionUpdate,
            () => showCoordinationItemEditSheet(
              context,
              item: item,
              onSaved: onChanged,
            ),
          ),
        ];
      case CoordinationItemKind.resolution:
        return [
          _actionButton(
            l10n.coordinationResolutionAcceptLabel,
            () => run(() => cubit.acceptResolution(item.id)),
          ),
          _actionButton(
            l10n.coordinationResolutionRejectLabel,
            () => run(() => cubit.rejectResolution(item.id)),
          ),
        ];
      case CoordinationItemKind.plan:
        return const [];
    }
  }

  Widget _actionButton(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }

  Future<void> _openItemThread(
    BuildContext context,
    CoordinationItem item,
  ) async {
    if (planItemSuppressesItemDiscussion(item)) {
      return;
    }
    await context.router.push<CoordinationItem?>(
      ItemDiscussionRoute(
        beaconId: item.beaconId,
        itemId: item.id,
        item: item,
      ),
    );
    if (context.mounted) {
      await context.read<BeaconYouItemsCubit>().fetch();
      onChanged?.call();
    }
  }
}
