import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/beacon_view/ui/message/help_offer_messages.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';
import '../bloc/inbox_cubit.dart';
import '../widget/inbox_item_tile.dart';
import '../widget/inbox_tombstone_card.dart';
import '../widget/rejection_dialog.dart';

@RoutePage()
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  String? _selectedNeedsBeaconId;
  String? _selectedWatchingBeaconId;

  void _selectNeedsItem(InboxItem item) {
    setState(() => _selectedNeedsBeaconId = item.beaconId);
  }

  void _selectWatchingItem(InboxItem item) {
    setState(() => _selectedWatchingBeaconId = item.beaconId);
  }

  @override
  Widget build(BuildContext context) {
    final inboxCubit = context.read<InboxCubit>();

    final screen = DefaultTabController(
      length: 2,
      child: _InboxMovedSnackBarDismisser(
        child: BlocListener<HomeTabReselectCubit, HomeTabReselectState>(
          listenWhen: (prev, curr) =>
              prev.inboxReselectCount != curr.inboxReselectCount,
          listener: (context, _) {
            inboxCubit.setSort(InboxSort.recent);
            DefaultTabController.of(context).animateTo(0);
          },
          child: BlocListener<InboxCubit, InboxState>(
            listenWhen: (prev, curr) =>
                curr.pendingMovedNudge != null &&
                prev.pendingMovedNudge != curr.pendingMovedNudge,
            listener: (context, state) {
              final msg = state.pendingMovedNudge;
              if (msg == null) return;
              final l10n = L10n.of(context)!;
              showSnackBar(
                context,
                text: msg.toL10n(l10n.localeName),
                action: SnackBarAction(
                  label: l10n.inboxViewInTab,
                  onPressed: () {
                    if (msg.navigatesToRejectedArchive) {
                      unawaited(openInboxRejectedArchive(context));
                    } else {
                      DefaultTabController.of(context).animateTo(msg.tabIndex);
                    }
                  },
                ),
              );
              context.read<InboxCubit>().clearPendingMovedNudge();
            },
            child: BlocBuilder<InboxCubit, InboxState>(
              buildWhen: (_, c) => c.isSuccess || c.isLoading,
              builder: (_, state) {
                final theme = Theme.of(context);
                final scheme = theme.colorScheme;
                final l10n = L10n.of(context)!;
                final useExpandedPane =
                    context.windowClass == WindowClass.expanded;

                late final Widget body;
                if (state.isLoading) {
                  body = const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                } else if (state.items.isEmpty) {
                  body = TabBarView(
                    children: [
                      _InboxTabKeepAlive(
                        storageKey: 'inbox-tab-needs-global-empty',
                        child: _inboxGlobalEmpty(
                          theme: theme,
                          l10n: l10n,
                          onOpenMyWork: () =>
                              AutoTabsRouter.of(context).setActiveIndex(0),
                        ),
                      ),
                      _InboxTabKeepAlive(
                        storageKey: 'inbox-tab-watching-global-empty',
                        child: _watchingQuietEmpty(theme: theme, l10n: l10n),
                      ),
                    ],
                  );
                } else {
                  body = BlocBuilder<NewStuffCubit, NewStuffState>(
                    buildWhen: (p, c) =>
                        p.inboxLastSeenMs != c.inboxLastSeenMs ||
                        p.maxInboxActivityMs != c.maxInboxActivityMs,
                    builder: (context, _) {
                      final newStuff = context.read<NewStuffCubit>();
                      return TabBarView(
                        children: [
                          _InboxTabKeepAlive(
                            storageKey: 'inbox-tab-needs',
                            child: _needsMeTabBody(
                              context,
                              inboxCubit,
                              state,
                              l10n,
                              newStuff,
                              onSelectItem: useExpandedPane
                                  ? _selectNeedsItem
                                  : null,
                            ),
                          ),
                          _InboxTabKeepAlive(
                            storageKey: 'inbox-tab-watching',
                            child: _watchingTabBody(
                              context,
                              inboxCubit,
                              state.watching,
                              l10n,
                              newStuff,
                              onSelectItem: useExpandedPane
                                  ? _selectWatchingItem
                                  : null,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                }

                final tt = context.tt;

                return Scaffold(
                  backgroundColor: scheme.surface,
                  appBar: TenturaTopBar.of(
                    context,
                    tone: TenturaTopBarTone.primary,
                    alignment: useExpandedPane
                        ? TenturaTopBarAlignment.fullWidth
                        : TenturaTopBarAlignment.content,
                    title: useExpandedPane
                        ? const SizedBox.shrink()
                        : const Row(
                            children: [
                              Expanded(child: _InboxTabStrip()),
                              _InboxSortButton(),
                            ],
                          ),
                    actions: useExpandedPane
                        ? null
                        : [
                            const _NotificationCenterButton(),
                            const _InboxOverflowMenu(),
                          ],
                    row: useExpandedPane
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              final masterWidth = inboxMasterPaneWidth(
                                constraints.maxWidth,
                                context.tt,
                              );
                              return Row(
                                children: [
                                  SizedBox(
                                    width: masterWidth,
                                    child: const Row(
                                      children: [
                                        Expanded(child: _InboxTabStrip()),
                                        _InboxSortButton(),
                                      ],
                                    ),
                                  ),
                                  const Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _NotificationCenterButton(),
                                          _InboxOverflowMenu(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          )
                        : null,
                  ),
                  body: SafeArea(
                    minimum: EdgeInsets.symmetric(
                      horizontal: tt.screenHPadding,
                    ),
                    child: useExpandedPane
                        ? _InboxExpandedBody(
                            tabView: body,
                            state: state,
                            selectedNeedsBeaconId: _selectedNeedsBeaconId,
                            selectedWatchingBeaconId: _selectedWatchingBeaconId,
                            onSelectNeeds: (item) => setState(
                              () => _selectedNeedsBeaconId = item.beaconId,
                            ),
                            onSelectWatching: (item) => setState(
                              () => _selectedWatchingBeaconId = item.beaconId,
                            ),
                          )
                        : TenturaContentColumn(child: body),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    return screen;
  }
}

double inboxMasterPaneWidth(double maxWidth, TenturaTokens tt) =>
    (tt.contentMaxWidth ?? maxWidth / 2).clamp(420.0, 560.0);

class _InboxExpandedBody extends StatelessWidget {
  const _InboxExpandedBody({
    required this.tabView,
    required this.state,
    required this.selectedNeedsBeaconId,
    required this.selectedWatchingBeaconId,
    required this.onSelectNeeds,
    required this.onSelectWatching,
  });

  final Widget tabView;
  final InboxState state;
  final String? selectedNeedsBeaconId;
  final String? selectedWatchingBeaconId;
  final ValueChanged<InboxItem> onSelectNeeds;
  final ValueChanged<InboxItem> onSelectWatching;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return LayoutBuilder(
      builder: (context, constraints) {
        final masterWidth = inboxMasterPaneWidth(constraints.maxWidth, tt);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: masterWidth, child: tabView),
            SizedBox(width: tt.screenHPadding),
            const TenturaVerticalHairline(),
            SizedBox(width: tt.screenHPadding),
            Expanded(
              child: _InboxExpandedPreview(
                state: state,
                selectedNeedsBeaconId: selectedNeedsBeaconId,
                selectedWatchingBeaconId: selectedWatchingBeaconId,
                onSelectNeeds: onSelectNeeds,
                onSelectWatching: onSelectWatching,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InboxExpandedPreview extends StatelessWidget {
  const _InboxExpandedPreview({
    required this.state,
    required this.selectedNeedsBeaconId,
    required this.selectedWatchingBeaconId,
    required this.onSelectNeeds,
    required this.onSelectWatching,
  });

  final InboxState state;
  final String? selectedNeedsBeaconId;
  final String? selectedWatchingBeaconId;
  final ValueChanged<InboxItem> onSelectNeeds;
  final ValueChanged<InboxItem> onSelectWatching;

  @override
  Widget build(BuildContext context) {
    final tabController = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: tabController,
      builder: (context, _) {
        final watchingTab = tabController.index == 1;
        final items = watchingTab ? state.watching : state.needsMe;
        final selectedId = watchingTab
            ? selectedWatchingBeaconId
            : selectedNeedsBeaconId;
        final selected = _selectedInboxItem(items, selectedId);
        if (selected == null) {
          final tt = context.tt;
          final l10n = L10n.of(context)!;
          return Center(
            child: Padding(
              padding: EdgeInsets.all(tt.screenHPadding),
              child: Text(
                watchingTab ? l10n.inboxWatchingEmptyCalm : l10n.inboxEmptyHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        final inboxCubit = context.read<InboxCubit>();
        final newStuff = context.read<NewStuffCubit>();
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.tt.contentMaxWidth!),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(vertical: context.tt.rowGap),
              child: InboxItemTile(
                key: ValueKey('preview-${selected.beaconId}'),
                item: selected,
                inboxHighlight: newStuff.inboxRowHighlight(
                  latestForwardAt: selected.latestForwardAt,
                  forwardCount: selected.forwardCount,
                  beaconActivityEpochMs:
                      selected.newStuffBeaconOnlyActivityEpochMs,
                ),
                onOpenBeacon: () => context.router.push(
                  BeaconViewRoute(
                    id: selected.beaconId,
                    entry: kBeaconEntryInbox,
                  ),
                ),
                onTap: () => unawaited(_onForwardItem(context, selected)),
                onWatch: watchingTab
                    ? null
                    : () {
                        onSelectWatching(selected);
                        inboxCubit.setWatching(selected.beaconId);
                      },
                onStopWatching: watchingTab
                    ? () {
                        onSelectNeeds(selected);
                        inboxCubit.stopWatching(selected.beaconId);
                      }
                    : null,
                onDismissFromInbox: () async {
                  final msg = await showInboxDismissDialog(context);
                  if (!context.mounted) return;
                  if (msg != null) {
                    await inboxCubit.reject(selected.beaconId, message: msg);
                  }
                },
                onCantHelp: () async {
                  final msg = await showRejectionDialog(context);
                  if (!context.mounted) return;
                  if (msg != null) {
                    await inboxCubit.reject(selected.beaconId, message: msg);
                  }
                },
                onOfferHelp: _inboxCardAllowsOfferHelp(selected)
                    ? () => _inboxOfferHelp(context, selected.beacon!)
                    : null,
                showCtaRow: !watchingTab,
                showProvenance: !watchingTab,
              ),
            ),
          ),
        );
      },
    );
  }
}

InboxItem? _selectedInboxItem(List<InboxItem> items, String? selectedId) {
  if (items.isEmpty) return null;
  if (selectedId != null) {
    for (final item in items) {
      if (item.beaconId == selectedId) {
        return item;
      }
    }
  }
  return items.first;
}

/// Hides the "beacon moved" snack bar when the user switches Needs me ↔
/// Watching or leaves the Inbox home tab (global [snackbarKey] messenger).
class _InboxMovedSnackBarDismisser extends StatefulWidget {
  const _InboxMovedSnackBarDismisser({required this.child});

  final Widget child;

  @override
  State<_InboxMovedSnackBarDismisser> createState() =>
      _InboxMovedSnackBarDismisserState();
}

class _InboxMovedSnackBarDismisserState
    extends State<_InboxMovedSnackBarDismisser> {
  TabController? _tabController;
  var _lastTabIndex = 0;

  void _clearSnackBars() {
    (ScaffoldMessenger.maybeOf(context) ?? snackbarKey.currentState)
        ?.clearSnackBars();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tc = DefaultTabController.of(context);
    if (!identical(_tabController, tc)) {
      _tabController?.removeListener(_onInboxTabChanged);
      _tabController = tc;
      _lastTabIndex = tc.index;
      _tabController!.addListener(_onInboxTabChanged);
    }
  }

  void _onInboxTabChanged() {
    final tc = _tabController;
    if (tc == null || tc.indexIsChanging) return;
    if (tc.index != _lastTabIndex) {
      _lastTabIndex = tc.index;
      _clearSnackBars();
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onInboxTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<NewStuffCubit, NewStuffState>(
        listenWhen: (prev, curr) =>
            prev.activeHomeTab == HomeTab.inbox &&
            curr.activeHomeTab != HomeTab.inbox,
        listener: (_, _) => _clearSnackBars(),
        child: widget.child,
      );
}

class _InboxTabKeepAlive extends StatefulWidget {
  const _InboxTabKeepAlive({
    required this.storageKey,
    required this.child,
  });

  final String storageKey;
  final Widget child;

  @override
  State<_InboxTabKeepAlive> createState() => _InboxTabKeepAliveState();
}

class _InboxTabKeepAliveState extends State<_InboxTabKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return KeyedSubtree(
      key: PageStorageKey<String>(widget.storageKey),
      child: widget.child,
    );
  }
}

/// Primary inbox tabs on the app bar row (no separate "Inbox" title).
class _InboxTabStrip extends StatelessWidget {
  const _InboxTabStrip();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return BlocSelector<InboxCubit, InboxState, int>(
      selector: (s) => s.needsMe.length,
      builder: (_, needsMeCount) {
        final tt = context.tt;
        return TenturaPrimaryTabBar(
          labelPadding: EdgeInsets.symmetric(horizontal: tt.rowGap),
          tabs: [
            Tab(text: '${l10n.inboxTabNeedsMe} ($needsMeCount)'),
            Tab(text: l10n.inboxTabWatching),
          ],
        );
      },
    );
  }
}

InboxSort _inboxSortAfter(InboxSort current) => switch (current) {
  InboxSort.recent => InboxSort.meritRank,
  InboxSort.meritRank => InboxSort.deadline,
  InboxSort.deadline => InboxSort.recent,
};

/// Cycles [InboxSort] on each tap; debounces bursts so one accidental double-tap
/// does not skip a mode.
class _InboxSortButton extends StatefulWidget {
  const _InboxSortButton();

  @override
  State<_InboxSortButton> createState() => _InboxSortButtonState();
}

class _InboxSortButtonState extends State<_InboxSortButton> {
  static const _debounce = Duration(milliseconds: 220);

  DateTime? _lastTap;

  void _onPressed(InboxSort current) {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < _debounce) {
      return;
    }
    _lastTap = now;
    context.read<InboxCubit>().setSort(_inboxSortAfter(current));
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

class _NotificationCenterButton extends StatelessWidget {
  const _NotificationCenterButton();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<NewStuffCubit, NewStuffState, int>(
        selector: (state) => state.notificationUnreadCount,
        builder: (context, unreadCount) => IconButton(
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            child: const Icon(Icons.notifications_none_outlined),
          ),
          tooltip: L10n.of(context)!.notifications,
          onPressed: () => context.router.push(
            const NotificationCenterRoute(),
          ),
        ),
      );
}

class _InboxOverflowMenu extends StatelessWidget {
  const _InboxOverflowMenu();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: context.tt.buttonHeight,
        minHeight: context.tt.buttonHeight,
      ),
      onSelected: (value) {
        if (value == 'rejected') {
          unawaited(openInboxRejectedArchive(context));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'rejected',
          child: Text(l10n.inboxRejectedTitle),
        ),
      ],
    );
  }
}

Widget _inboxGlobalEmpty({
  required ThemeData theme,
  required L10n l10n,
  required VoidCallback onOpenMyWork,
}) {
  final scheme = theme.colorScheme;
  final tt = theme.extension<TenturaTokens>()!;
  return Center(
    child: Padding(
      padding: EdgeInsets.all(tt.screenHPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: scheme.onSurfaceVariant,
          ),
          SizedBox(height: tt.sectionGap),
          Text(
            l10n.inboxEmpty,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: tt.rowGap),
          Text(
            l10n.inboxEmptyHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: tt.sectionGap),
          TenturaTextAction(
            label: l10n.inboxViewMyWork,
            onPressed: onOpenMyWork,
          ),
        ],
      ),
    ),
  );
}

Widget _watchingQuietEmpty({
  required ThemeData theme,
  required L10n l10n,
}) {
  final tt = theme.extension<TenturaTokens>()!;
  return Center(
    child: Padding(
      padding: EdgeInsets.all(tt.screenHPadding),
      child: Text(
        l10n.inboxWatchingEmptyCalm,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

Widget _needsMeTabBody(
  BuildContext context,
  InboxCubit inboxCubit,
  InboxState state,
  L10n l10n,
  NewStuffCubit newStuff, {
  ValueChanged<InboxItem>? onSelectItem,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final tt = context.tt;
  final tombstones = state.tombstonesLast24h;
  final needsMe = state.needsMe;

  if (tombstones.isEmpty && needsMe.isEmpty) {
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

  return RefreshIndicator.adaptive(
    onRefresh: inboxCubit.fetch,
    child: CustomScrollView(
      key: const PageStorageKey<String>('inbox-needs-me-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (tombstones.isNotEmpty || needsMe.isNotEmpty)
          SliverToBoxAdapter(child: SizedBox(height: tt.rowGap)),
        if (tombstones.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(
                top: tt.tightGap * 2,
                bottom: tt.rowGap,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.inboxTombstoneSectionTitle,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: tt.rowGap),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(TenturaRadii.avatar),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: tt.rowGap,
                        vertical: tt.tightGap * 2,
                      ),
                      child: Text(
                        l10n.inboxTombstoneLast24h,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList.separated(
            itemCount: tombstones.length,
            separatorBuilder: (_, _) => SizedBox(height: tt.rowGap),
            itemBuilder: (_, i) {
              final item = tombstones[i];
              return InboxTombstoneCard(
                key: ValueKey('tombstone-${item.beaconId}'),
                item: item,
                onOpen: () => context.router.push(
                  BeaconViewRoute(id: item.beaconId, entry: kBeaconEntryInbox),
                ),
                onDismiss: () => inboxCubit.dismissTombstone(item.beaconId),
              );
            },
          ),
          SliverToBoxAdapter(child: SizedBox(height: tt.sectionGap)),
        ],
        if (needsMe.isNotEmpty) ...[
          SliverList.separated(
            itemCount: needsMe.length,
            separatorBuilder: (_, _) => SizedBox(height: tt.rowGap),
            itemBuilder: (_, i) {
              final item = needsMe[i];
              return InboxItemTile(
                key: ValueKey(item.beaconId),
                item: item,
                inboxHighlight: newStuff.inboxRowHighlight(
                  latestForwardAt: item.latestForwardAt,
                  forwardCount: item.forwardCount,
                  beaconActivityEpochMs: item.newStuffBeaconOnlyActivityEpochMs,
                ),
                onOpenBeacon: onSelectItem == null
                    ? () => context.router.push(
                        BeaconViewRoute(
                          id: item.beaconId,
                          entry: kBeaconEntryInbox,
                        ),
                      )
                    : () => onSelectItem(item),
                onTap: () => unawaited(_onForwardItem(context, item)),
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
                onOfferHelp: _inboxCardAllowsOfferHelp(item)
                    ? () => _inboxOfferHelp(context, item.beacon!)
                    : null,
              );
            },
          ),
        ] else if (tombstones.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(
                left: tt.rowGap,
                right: tt.rowGap,
                bottom: tt.sectionGap,
              ),
              child: Text(
                l10n.inboxNeedsMeEmptyCalm,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: tt.sectionGap)),
      ],
    ),
  );
}

Widget _watchingTabBody(
  BuildContext context,
  InboxCubit inboxCubit,
  List<InboxItem> items,
  L10n l10n,
  NewStuffCubit newStuff, {
  ValueChanged<InboxItem>? onSelectItem,
}) {
  final theme = Theme.of(context);
  final tt = context.tt;

  if (items.isEmpty) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tt.screenHPadding),
        child: Text(
          l10n.inboxWatchingEmptyCalm,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  return RefreshIndicator.adaptive(
    onRefresh: inboxCubit.fetch,
    child: ListView.separated(
      key: const PageStorageKey<String>('inbox-watching-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(vertical: tt.rowGap),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(height: tt.rowGap),
      itemBuilder: (_, i) {
        final item = items[i];
        return InboxItemTile(
          key: ValueKey(item.beaconId),
          item: item,
          inboxHighlight: newStuff.inboxRowHighlight(
            latestForwardAt: item.latestForwardAt,
            forwardCount: item.forwardCount,
            beaconActivityEpochMs: item.newStuffBeaconOnlyActivityEpochMs,
          ),
          onOpenBeacon: onSelectItem == null
              ? () => context.router.push(
                  BeaconViewRoute(id: item.beaconId, entry: kBeaconEntryInbox),
                )
              : () => onSelectItem(item),
          onTap: () => unawaited(_onForwardItem(context, item)),
          onStopWatching: () => inboxCubit.stopWatching(item.beaconId),
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
          onOfferHelp: _inboxCardAllowsOfferHelp(item)
              ? () => _inboxOfferHelp(context, item.beacon!)
              : null,
          showCtaRow: false,
          showProvenance: false,
        );
      },
    ),
  );
}

/// Pushes full-screen rejected archive, then refreshes the tab inbox when popped.
Future<void> openInboxRejectedArchive(BuildContext context) async {
  final cubit = context.read<InboxCubit>();
  await context.router.push(const InboxRejectedRoute());
  if (!context.mounted) return;
  await cubit.fetch();
}

bool _inboxCardAllowsOfferHelp(InboxItem item) {
  final b = item.beacon;
  return b != null &&
      b.allowsNewHelpOfferAsNonAuthor &&
      item.status != InboxItemStatus.rejected;
}

Future<void> _inboxOfferHelp(BuildContext context, Beacon beacon) async {
  final l10n = L10n.of(context)!;
  final useOfferHelpAnyway = beacon.status == BeaconStatus.enoughHelp;
  final outcome = await HelpOfferMessageDialog.show(
    context,
    title: useOfferHelpAnyway
        ? l10n.dialogOfferHelpAnywayTitle
        : l10n.dialogOfferHelpTitle,
    hintText: l10n.hintOfferHelpMessage,
    allowEmptyMessage: true,
    showHelpTypeChips: true,
  );
  if (outcome == null || !context.mounted) return;
  final ok = await GetIt.I<ForwardRepository>().offerHelp(
    beaconId: beacon.id,
    message: outcome.message,
    helpTypes: outcome.helpTypesWire,
  );
  if (!context.mounted || !ok) return;
  GetIt.I<UiEffectPort>().emit(
    ShowMessage(HelpOfferedForwardNudgeMessage(beacon.id)),
  );
}

Future<void> _onForwardItem(BuildContext context, InboxItem item) async {
  final didForward = await context.router.push<bool>(
    ForwardBeaconRoute(beaconId: item.beaconId),
  );
  if (!context.mounted || didForward != true) return;
  if (!_inboxCardAllowsOfferHelp(item)) return;
  final l10n = L10n.of(context)!;
  showSnackBar(
    context,
    text: l10n.nudgeOfferHelpAfterForward,
    action: SnackBarAction(
      label: l10n.labelOfferHelp,
      onPressed: () => unawaited(_inboxOfferHelp(context, item.beacon!)),
    ),
  );
}
