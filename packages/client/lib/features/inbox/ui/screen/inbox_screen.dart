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
import '../message/inbox_messages.dart';
import '../widget/inbox_item_tile.dart';
import '../widget/inbox_tombstone_card.dart';
import '../widget/rejection_dialog.dart';

@RoutePage()
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inboxCubit = context.read<InboxCubit>();

    return DefaultTabController(
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
                curr.status is StateIsMessaging &&
                (curr.status as StateIsMessaging).message
                    is InboxBeaconMovedMessage,
            listener: (context, state) {
              final msg =
                  (state.status as StateIsMessaging).message
                      as InboxBeaconMovedMessage;
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
            },
            child: BlocBuilder<InboxCubit, InboxState>(
              buildWhen: (_, c) => c.isSuccess || c.isLoading || c.hasError,
              builder: (_, state) {
                final theme = Theme.of(context);
                final scheme = theme.colorScheme;
                final l10n = L10n.of(context)!;

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
                  appBar: AppBar(
                    // Same fill as the inbox card Offer Help [FilledButton] default style.
                    backgroundColor: scheme.primary,
                    surfaceTintColor: scheme.primary,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    toolbarHeight: tt.appBarHeight,
                    foregroundColor: scheme.onPrimary,
                    iconTheme: IconThemeData(color: scheme.onPrimary),
                    // Tab root: never show a back control (some nested routes still
                    // reserve leading width unless this is explicit).
                    automaticallyImplyLeading: false,
                    titleSpacing: tt.iconTextGap,
                    title: const Row(
                      children: [
                        Expanded(child: _InboxTabStrip()),
                        _InboxSortButton(),
                      ],
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.notifications_none_outlined),
                        tooltip: l10n.notifications,
                        onPressed: () =>
                            context.router.pushPath(kPathNotifications),
                      ),
                      const _InboxOverflowMenu(),
                    ],
                  ),
                  body: SafeArea(
                    minimum: EdgeInsets.symmetric(
                      horizontal: tt.screenHPadding,
                    ),
                    child: body,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
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
            prev.activeHomeTabIndex == 1 && curr.activeHomeTabIndex != 1,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context)!;

    return BlocSelector<InboxCubit, InboxState, int>(
      selector: (s) => s.needsMe.length,
      builder: (_, needsMeCount) {
        final tt = context.tt;
        return TabBar(
          automaticIndicatorColorAdjustment: false,
          tabAlignment: TabAlignment.start,
          isScrollable: true,
          labelPadding: EdgeInsets.symmetric(horizontal: tt.rowGap),
          labelColor: scheme.onPrimary,
          unselectedLabelColor: scheme.onPrimary.withValues(alpha: 0.72),
          indicatorColor: scheme.onPrimary,
          dividerColor: scheme.primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onPrimary,
          ),
          unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: scheme.onPrimary.withValues(alpha: 0.72),
          ),
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
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.inboxEmpty,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.inboxEmptyHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
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
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
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
  NewStuffCubit newStuff,
) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final tt = context.tt;
  final tombstones = state.tombstonesLast24h;
  final needsMe = state.needsMe;

  if (tombstones.isEmpty && needsMe.isEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 12),
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
          const SliverToBoxAdapter(child: SizedBox(height: kSpacingSmall)),
        if (tombstones.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, kSpacingSmall),
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
                  const SizedBox(width: kSpacingSmall),
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
            separatorBuilder: (_, _) => const SizedBox(height: kSpacingSmall),
            itemBuilder: (_, i) {
              final item = tombstones[i];
              return InboxTombstoneCard(
                key: ValueKey('tombstone-${item.beaconId}'),
                item: item,
                onOpen: () => context.router.pushPath(
                  '$kPathBeaconView/${item.beaconId}?$kQueryBeaconEntry=$kBeaconEntryInbox',
                ),
                onDismiss: () => inboxCubit.dismissTombstone(item.beaconId),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
        ],
        if (needsMe.isNotEmpty) ...[
          SliverList.separated(
            itemCount: needsMe.length,
            separatorBuilder: (_, _) => const SizedBox(height: kSpacingSmall),
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
                onOpenBeacon: () => context.router.pushPath(
                  '$kPathBeaconView/${item.beaconId}?$kQueryBeaconEntry=$kBeaconEntryInbox',
                ),
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
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                l10n.inboxNeedsMeEmptyCalm,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    ),
  );
}

Widget _watchingTabBody(
  BuildContext context,
  InboxCubit inboxCubit,
  List<InboxItem> items,
  L10n l10n,
  NewStuffCubit newStuff,
) {
  final theme = Theme.of(context);

  if (items.isEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
      padding: kPaddingSmallV,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: kSpacingSmall),
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
          onOpenBeacon: () => context.router.pushPath(
            '$kPathBeaconView/${item.beaconId}?$kQueryBeaconEntry=$kBeaconEntryInbox',
          ),
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
  await context.router.pushPath(kPathInboxRejected);
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
