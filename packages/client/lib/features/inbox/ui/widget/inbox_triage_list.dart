import 'dart:async';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/enum.dart';
import '../bloc/inbox_cubit.dart';
import 'inbox_card_actions.dart';
import 'inbox_item_tile.dart';
import 'rejection_dialog.dart';

InboxSort inboxSortAfter(InboxSort current) => switch (current) {
  InboxSort.recent => InboxSort.meritRank,
  InboxSort.meritRank => InboxSort.deadline,
  InboxSort.deadline => InboxSort.recent,
};

/// Sort control for the triage route (extracted from the former inbox app bar).
class InboxTriageSortButton extends StatefulWidget {
  const InboxTriageSortButton({super.key});

  @override
  State<InboxTriageSortButton> createState() => _InboxTriageSortButtonState();
}

class _InboxTriageSortButtonState extends State<InboxTriageSortButton> {
  static const _debounce = Duration(milliseconds: 220);

  DateTime? _lastTap;

  void _onPressed(InboxSort current) {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < _debounce) {
      return;
    }
    _lastTap = now;
    context.read<InboxCubit>().setSort(inboxSortAfter(current));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;

    return BlocSelector<InboxCubit, InboxState, InboxSort>(
      selector: (s) => s.sort,
      builder: (context, sort) {
        final scheme = theme.colorScheme;
        final tt = context.tt;
        final label = switch (sort) {
          InboxSort.recent => l10n.inboxSortRecent,
          InboxSort.meritRank => l10n.inboxSortMeritRank,
          InboxSort.deadline => l10n.inboxSortDeadline,
        };
        return Tooltip(
          message: '${l10n.inboxSortMenuTitle}: $label',
          child: TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: tt.tightGap * 2),
              minimumSize: Size(tt.buttonHeight, tt.buttonHeight),
              tapTargetSize: MaterialTapTargetSize.padded,
              foregroundColor: scheme.onPrimary,
            ),
            onPressed: () => _onPressed(sort),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: tt.buttonHeight * 2),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.labelLarge(scheme.onPrimary).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.swap_vert,
                  size: tt.iconSize,
                  color: scheme.onPrimary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Needs-me inbox body with card affordances (UNIT 14 triage route mounts this).
class InboxTriageList extends StatelessWidget {
  const InboxTriageList({
    required this.inboxCubit,
    required this.state,
    required this.attentionMarkerIds,
    super.key,
  });

  final InboxCubit inboxCubit;
  final InboxState state;
  final Set<String> attentionMarkerIds;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final needsMe = state.needsMe;

    if (needsMe.isEmpty) {
      return _needsMeEmpty(context, l10n);
    }

    final tt = context.tt;

    return RefreshIndicator.adaptive(
      onRefresh: inboxCubit.fetch,
      child: CustomScrollView(
        key: const PageStorageKey<String>('inbox-needs-me-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: tt.rowGap)),
          SliverList.separated(
              itemCount: needsMe.length,
              separatorBuilder: (_, _) => SizedBox(height: tt.rowGap),
              itemBuilder: (_, i) {
                final item = needsMe[i];
                return InboxItemTile(
                  key: ValueKey(item.beaconId),
                  item: item,
                  attentionMarked: attentionMarkerIds.contains(item.beaconId),
                  onOpenBeacon: () => context.router.push(
                    BeaconViewRoute(
                      id: item.beaconId,
                      entry: kBeaconEntryInbox,
                    ),
                  ),
                  onTap: item.beacon?.allowsForward == true
                      ? () => unawaited(inboxForwardItem(context, item))
                      : null,
                  onWatch: () => inboxCubit.setWatching(item.beaconId),
                  onDismissFromInbox: () async {
                    final msg = await showInboxDismissDialog(context);
                    if (!context.mounted) return;
                    if (msg != null) {
                      await inboxCubit.reject(item.beaconId, message: msg);
                    }
                  },
                  onCantHelp: () async {
                    final msg = await showRejectionDialog(context);
                    if (!context.mounted) return;
                    if (msg != null) {
                      await inboxCubit.reject(item.beaconId, message: msg);
                    }
                  },
                  onOfferHelp: inboxCardAllowsOfferHelp(item)
                      ? () => inboxOfferHelp(context, item.beacon!)
                      : null,
                );
              },
            ),
          SliverToBoxAdapter(child: SizedBox(height: tt.sectionGap)),
        ],
      ),
    );
  }

  Widget _needsMeEmpty(BuildContext context, L10n l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tt.screenHPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.inboxNeedsMeEmptyCalm,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: tt.sectionGap),
            TenturaTextAction(
              label: l10n.inboxViewMyWork,
              onPressed: () => AutoTabsRouter.of(context).setActiveIndex(0),
            ),
          ],
        ),
      ),
    );
  }
}
