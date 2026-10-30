import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/features/home/ui/widget/home_account_avatar_button.dart';
import 'package:tentura/features/home/ui/widget/own_paused_chip.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura_root/domain/enums.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';
import 'package:tentura/ui/widget/first_load_gate.dart';
import 'package:tentura/ui/widget/show_anchored_popup_menu.dart';

import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/widget/home_orientation_panel.dart';
import 'package:tentura/features/home/ui/widget/orientation_inviter_builder.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';

import 'package:tentura/features/my_work/domain/derive_my_work_sections.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/my_desk_caught_up.dart';
import 'package:tentura/ui/widget/caught_up_panel.dart';
import '../bloc/my_work_cubit.dart';
import '../widget/my_work_cards.dart';
import '../widget/my_work_empty_body.dart';

@RoutePage()
class MyWorkScreen extends StatefulWidget implements AutoRouteWrapper {
  const MyWorkScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => this;

  @override
  State<MyWorkScreen> createState() => _MyWorkScreenState();
}

class _MyWorkScreenState extends State<MyWorkScreen> {
  final ScrollController _listScrollController = ScrollController();

  @override
  void dispose() {
    _listScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final useExpandedPane = context.windowClass == WindowClass.expanded;
    final useCompactTopBar = context.windowClass == WindowClass.compact;
    final tt = context.tt;
    // Work is about Requests: «+» starts one. Posts start from Posts' «+».
    final createButton = IconButton(
      tooltip: l10n.newBeacon,
      onPressed: () => context.read<ScreenCubit>().showBeaconCreate(),
      icon: const Icon(Icons.add),
    );
    return BlocListener<HomeTabReselectCubit, HomeTabReselectState>(
      listenWhen: (prev, curr) =>
          prev.myWorkReselectCount != curr.myWorkReselectCount,
      listener: (context, _) {
        context.read<MyWorkCubit>()
          ..setFilter(MyWorkFilter.active)
          ..setSort(MyWorkSort.recent);
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: TenturaTopBar.of(
          context,
          tone: TenturaTopBarTone.primary,
          alignment: useExpandedPane
              ? TenturaTopBarAlignment.fullWidth
              : TenturaTopBarAlignment.content,
          title: useCompactTopBar
              ? const SizedBox.shrink()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // NavigationToolbar can leave the title slot narrower
                    // than one control while its leading and actions are
                    // being measured. Keep the compact custom row unchanged;
                    // on this transient non-compact path, omit controls that
                    // cannot retain their tap target instead of overflowing.
                    if (constraints.maxWidth < tt.buttonHeight) {
                      return const SizedBox.shrink();
                    }
                    return const _MyWorkTitleControls();
                  },
                ),
          actions: useCompactTopBar ? null : [createButton],
          // NavigationToolbar balances its middle against the full trailing
          // action width. With filter + sort in the middle and two actions at
          // 390px, that can leave only a few pixels for the middle Row. The
          // compact bar is one explicit flex row so the filter owns the
          // shrinkable remainder while sort and icon actions keep tap targets.
          row: useCompactTopBar
              ? Row(
                  children: [
                    const Expanded(child: _MyWorkTitleControls()),
                    createButton,
                  ],
                )
              : null,
          account: useCompactTopBar
              ? const HomeAccountAvatarButton()
              : homeTopBarAccount(context),
          bottom: useCompactTopBar
              ? const _MyWorkTopBarPausedBottom()
              : null,
        ),
        body: SafeArea(
          minimum: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
          child: _MyWorkBody(
            listScrollController: _listScrollController,
          ),
        ),
      ),
    );
  }
}

class _MyWorkTopBarPausedBottom extends StatelessWidget
    implements PreferredSizeWidget {
  const _MyWorkTopBarPausedBottom({
    this.profileCubit,
    this.clock,
    super.key,
  });

  final ProfileCubit? profileCubit;
  final DateTime Function()? clock;

  ProfileCubit? _resolveCubit() =>
      profileCubit ??
      (GetIt.I.isRegistered<ProfileCubit>() ? GetIt.I<ProfileCubit>() : null);

  @override
  Size get preferredSize {
    final cubit = _resolveCubit();
    if (cubit == null) return Size.zero;
    final availability = cubit.state.profile.availability;
    final todayUtc = availabilityTodayUtc(clock);
    final isPaused = availability.resumeOn != null &&
        availability.effectiveOn(todayUtc) == AvailabilityView.paused;
    return isPaused ? const Size.fromHeight(28) : Size.zero;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _resolveCubit();
    if (cubit == null) return const SizedBox.shrink();
    return BlocBuilder<ProfileCubit, ProfileState>(
      bloc: cubit,
      buildWhen: (p, c) => p.profile.availability != c.profile.availability,
      builder: (context, state) {
        final availability = state.profile.availability;
        final todayUtc = availabilityTodayUtc(clock);
        if (availability.resumeOn == null ||
            availability.effectiveOn(todayUtc) != AvailabilityView.paused) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.centerRight,
          child: OwnPausedChip(
            profileCubit: cubit,
            clock: clock,
            dense: true,
          ),
        );
      },
    );
  }
}

String _labelForFilter(L10n l10n, MyWorkFilter f) => switch (f) {
  MyWorkFilter.active => l10n.myWorkFilterActive,
  MyWorkFilter.all => l10n.myWorkFilterAll,
  MyWorkFilter.authored => l10n.myWorkFilterAuthored,
  MyWorkFilter.helpOffered => l10n.myWorkFilterHelpOffered,
  MyWorkFilter.drafts => l10n.myWorkFilterDrafts,
  MyWorkFilter.archived => l10n.myWorkFilterArchived,
};

Future<void> _showMyWorkFilterMenu(
  BuildContext buttonContext,
  L10n l10n,
) async {
  final selected = await showAnchoredPopupMenu<MyWorkFilter>(
    anchorContext: buttonContext,
    items: [
      for (final f in kMyWorkFilterMenuOrder)
        PopupMenuItem<MyWorkFilter>(
          value: f,
          child: Text(_labelForFilter(l10n, f)),
        ),
    ],
  );
  if (selected != null && buttonContext.mounted) {
    buttonContext.read<MyWorkCubit>().setFilter(selected);
  }
}

/// The title with the filter and sort controls after it. Their labels name
/// the current filter and sort; when the bar is too narrow for them, the sort
/// and then the filter turn into icon buttons (labels move to tooltips).
class _MyWorkTitleControls extends StatelessWidget {
  const _MyWorkTitleControls();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocSelector<
      MyWorkCubit,
      MyWorkState,
      ({MyWorkFilter filter, MyWorkSort sort})
    >(
      selector: (s) => (filter: s.filter, sort: s.sort),
      builder: (context, view) => LayoutBuilder(
        builder: (context, constraints) {
          final tt = context.tt;
          final scheme = Theme.of(context).colorScheme;
          final titleStyle = TenturaText.titleLarge(scheme.onSurface);
          final filterLabel = _labelForFilter(l10n, view.filter);
          final sortLabel = _labelForSort(l10n, view.sort);
          final title =
              TenturaTopBarControl.textWidth(context, l10n.myWork, titleStyle) +
              tt.iconTextGap;
          final filterWide = TenturaTopBarControl.expandedWidth(
            context,
            filterLabel,
          );
          final sortWide = TenturaTopBarControl.expandedWidth(
            context,
            sortLabel,
          );
          final icon = TenturaTopBarControl.collapsedWidth(context);
          final max = constraints.maxWidth;
          final collapseSort = title + filterWide + sortWide > max;
          final collapseFilter =
              collapseSort && title + filterWide + icon > max;
          return Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        l10n.myWork,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    SizedBox(width: tt.iconTextGap),
                    // The screen names itself like Activity does; the filter
                    // follows the title instead of standing in for it.
                    Flexible(
                      child: TenturaTopBarControl(
                        label: filterLabel,
                        icon: Icons.filter_list,
                        trailingIcon: Icons.arrow_drop_down,
                        tooltip: l10n.myWorkFilterMenuTooltip,
                        collapsed: collapseFilter,
                        onPressed: () =>
                            unawaited(_showMyWorkFilterMenu(context, l10n)),
                      ),
                    ),
                  ],
                ),
              ),
              _MyWorkSortButton(
                label: sortLabel,
                sort: view.sort,
                collapsed: collapseSort,
              ),
            ],
          );
        },
      ),
    );
  }
}

String _labelForSort(L10n l10n, MyWorkSort sort) => switch (sort) {
  MyWorkSort.recent => l10n.myWorkSortRecent,
  MyWorkSort.oldest => l10n.myWorkSortOldest,
  MyWorkSort.alphabetical => l10n.myWorkSortAlphabetical,
};

MyWorkSort _myWorkSortAfter(MyWorkSort current) => switch (current) {
  MyWorkSort.recent => MyWorkSort.oldest,
  MyWorkSort.oldest => MyWorkSort.alphabetical,
  MyWorkSort.alphabetical => MyWorkSort.recent,
};

/// #431: the icon names the current order, like the label does.
IconData _iconForSort(MyWorkSort sort) => switch (sort) {
  MyWorkSort.recent => Icons.arrow_downward,
  MyWorkSort.oldest => Icons.arrow_upward,
  MyWorkSort.alphabetical => Icons.sort_by_alpha,
};

class _MyWorkSortButton extends StatefulWidget {
  const _MyWorkSortButton({
    required this.label,
    required this.sort,
    required this.collapsed,
  });

  final String label;
  final MyWorkSort sort;
  final bool collapsed;

  @override
  State<_MyWorkSortButton> createState() => _MyWorkSortButtonState();
}

class _MyWorkSortButtonState extends State<_MyWorkSortButton> {
  static const _debounce = Duration(milliseconds: 220);

  DateTime? _lastTap;

  void _onPressed() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < _debounce) {
      return;
    }
    _lastTap = now;
    final cubit = context.read<MyWorkCubit>();
    cubit.setSort(_myWorkSortAfter(cubit.state.sort));
  }

  @override
  Widget build(BuildContext context) => TenturaTopBarControl(
    label: widget.label,
    icon: _iconForSort(widget.sort),
    tooltip: L10n.of(context)!.myWorkSortMenuTooltip,
    collapsed: widget.collapsed,
    onPressed: _onPressed,
  );
}

class _MyWorkBody extends StatelessWidget {
  const _MyWorkBody({
    required this.listScrollController,
  });

  final ScrollController listScrollController;

  bool _shouldRebuild(MyWorkState p, MyWorkState c) {
    if (p.firstLoadDone != c.firstLoadDone ||
        p.status != c.status ||
        p.filter != c.filter ||
        p.sort != c.sort ||
        p.archivedFetchInProgress != c.archivedFetchInProgress ||
        p.hasError != c.hasError) {
      return true;
    }
    if (p.nonArchivedCards.length != c.nonArchivedCards.length ||
        p.archivedCards.length != c.archivedCards.length) {
      return true;
    }
    if (p.draftCount != c.draftCount ||
        p.archivedCountHint != c.archivedCountHint) {
      return true;
    }
    if (p.nonArchivedCards != c.nonArchivedCards ||
        p.archivedCards != c.archivedCards) {
      return true;
    }
    if (p.attentionByBeacon != c.attentionByBeacon ||
        p.attentionLoaded != c.attentionLoaded) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<MyWorkCubit>();
    final tt = context.tt;
    return BlocListener<MyWorkCubit, MyWorkState>(
      listenWhen: (previous, current) =>
          current.hasError && previous.loadError != current.loadError,
      listener: (context, state) {
        final error = state.loadError!;
        final details = describeScreenLoadError(error: error, l10n: l10n);
        logScreenLoadError(label: 'MyWork', error: error, details: details);
        if (error is AuthSessionLostException) {
          GetIt.I<AuthCubit>().noteAuthSessionLoss(error);
        }
      },
      child: BlocBuilder<MyWorkCubit, MyWorkState>(
        buildWhen: _shouldRebuild,
        builder: (_, state) {
          final listBody = _MyWorkListBody(
            state: state,
            cubit: cubit,
            l10n: l10n,
            tt: tt,
            scrollController: listScrollController,
          );
          return TenturaFirstLoadGate(
            ready: state.firstLoadDone,
            error: state.loadError,
            onRetry: cubit.fetch,
            onSignInAgain: () => unawaited(
              GetIt.I<RootRouter>().push(RecoverRoute()),
            ),
            child: TenturaContentColumn(child: listBody),
          );
        },
      ),
    );
  }
}

class _MyWorkListBody extends StatelessWidget {
  const _MyWorkListBody({
    required this.state,
    required this.cubit,
    required this.l10n,
    required this.tt,
    required this.scrollController,
  });

  final MyWorkState state;
  final MyWorkCubit cubit;
  final L10n l10n;
  final TenturaTokens tt;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && !state.firstLoadDone) {
      return const SizedBox.shrink();
    }
    if (state.hasError) {
      final error = state.loadError!;
      final details = describeScreenLoadError(error: error, l10n: l10n);
      return ScreenLoadErrorPanel(
        details: details,
        onRetry: cubit.fetch,
        onSignInAgain: details.kind == ScreenLoadErrorKind.session
            ? () => unawaited(
                GetIt.I<RootRouter>().push(RecoverRoute()),
              )
            : null,
      );
    }
    if (state.filter == MyWorkFilter.archived &&
        !state.archivedDataFetched &&
        state.archivedFetchInProgress) {
      return const Center(
        child: CircularProgressIndicator.adaptive(),
      );
    }
    final cards = state.visibleCards;
    if (cards.isEmpty) {
      return BlocSelector<
        HomeActivationCubit,
        HomeActivationState,
        OrientationDecision
      >(
        selector: (s) => s.decideFor(state.filter),
        builder: (context, decision) {
          return BlocSelector<
            InboxOperationalCubit,
            InboxOperationalState,
            (int, bool)
          >(
            selector: (s) => (s.needsMeCount, s.loadComplete),
            builder: (context, inboxMeta) {
              final (inboxNeedsMeCount, inboxLoadComplete) = inboxMeta;
              return RefreshIndicator.adaptive(
                onRefresh: cubit.fetch,
                child: CustomScrollView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    switch (decision) {
                      OrientationDecision.show => SliverToBoxAdapter(
                        child: OrientationInviterBuilder(
                          builder: (context, inviter) => HomeOrientationPanel(
                            inviter: inviter,
                            onOpenInviter: inviter == null
                                ? null
                                : () => context
                                      .read<ScreenCubit>()
                                      .showBeaconsOf(inviter.id),
                            inboxNeedsMeCount: inboxNeedsMeCount,
                            onCreateBeacon: () =>
                                context.read<ScreenCubit>().showBeaconCreate(),
                            onOpenInbox: () =>
                                AutoTabsRouter.of(context).setActiveIndex(
                                  HomeTabSpec.forTab(HomeTab.inbox).index,
                                ),
                            onOpenConstellation: () =>
                                AutoTabsRouter.of(context).setActiveIndex(
                                  HomeTabSpec.forTab(
                                    HomeTab.constellation,
                                  ).index,
                                ),
                            onOpenTab: (tab) => AutoTabsRouter.of(
                              context,
                            ).setActiveIndex(HomeTabSpec.forTab(tab).index),
                            onDismiss: () =>
                                context.read<HomeActivationCubit>().dismiss(),
                          ),
                        ),
                      ),
                      OrientationDecision.ordinaryEmpty => SliverFillRemaining(
                        hasScrollBody: false,
                        child: MyWorkEmptyBody(
                          filter: state.filter,
                          draftCount: state.draftCount,
                          archivedCountHint: state.archivedCountHint,
                          inboxNeedsMeCount: inboxNeedsMeCount,
                          inboxLoadComplete: inboxLoadComplete,
                          onCreateBeacon: () =>
                              context.read<ScreenCubit>().showBeaconCreate(),
                          onOpenInbox: () =>
                              AutoTabsRouter.of(context).setActiveIndex(
                                HomeTabSpec.forTab(HomeTab.inbox).index,
                              ),
                          onOpenConstellation: () =>
                              AutoTabsRouter.of(context).setActiveIndex(
                                HomeTabSpec.forTab(HomeTab.constellation).index,
                              ),
                          onShowDrafts: () =>
                              cubit.setFilter(MyWorkFilter.drafts),
                          onShowArchived: () =>
                              cubit.setFilter(MyWorkFilter.archived),
                        ),
                      ),
                      OrientationDecision.undecided => SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      ),
                    },
                  ],
                ),
              );
            },
          );
        },
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: cubit.fetch,
      child: CustomScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: _myWorkRedesignSlivers(
          context: context,
          l10n: l10n,
          tt: tt,
          state: state,
          cards: cards,
        ),
      ),
    );
  }
}

List<Widget> _myWorkRedesignSlivers({
  required BuildContext context,
  required L10n l10n,
  required TenturaTokens tt,
  required MyWorkState state,
  required List<MyWorkCardViewModel> cards,
}) {
  final sections = deriveMyWorkSections(
    cards: cards,
    attentionByBeacon: state.attentionByBeacon,
    filter: state.filter,
  );
  final slivers = <Widget>[
    SliverPadding(
      padding: EdgeInsets.only(top: tt.rowGap),
      sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
    ),
    // D18 — "My Desk can be attention-clear while authored / active-help
    // Requests remain." One quiet line, above work that is still listed: it
    // says nothing is *waiting on a response*, and deliberately nothing about
    // the list below being empty or finished.
    if (myDeskIsCaughtUp(
      filter: state.filter,
      cards: cards,
      attentionByBeacon: state.attentionByBeacon,
      attentionLoaded: state.attentionLoaded,
      hasError: state.hasError,
    ))
      SliverToBoxAdapter(
        child: CaughtUpPanel(title: l10n.myWorkCaughtUp, compact: true),
      ),
    // #491 — the Archived filter outlives a re-entry of the Requests tab
    // (the cubit sits above the tab shell), so say plainly that this is the
    // archive and offer one tap back to Active (the sort is kept).
    if (state.filter == MyWorkFilter.archived &&
        state.nonArchivedCards.isNotEmpty)
      SliverToBoxAdapter(
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.myWorkShowingArchived,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
            ),
            TenturaTextAction(
              label: l10n.myWorkShowActive,
              onPressed: () =>
                  context.read<MyWorkCubit>().setFilter(MyWorkFilter.active),
            ),
          ],
        ),
      ),
  ];
  for (final group in sections) {
    if (group.section != MyWorkDeskSection.unlabeled) {
      final headerLabel = switch (group.section) {
        MyWorkDeskSection.needsYou => l10n.myWorkSectionNeedsYou,
        MyWorkDeskSection.inProgress => l10n.myWorkSectionInProgress,
        MyWorkDeskSection.finished => l10n.myWorkSectionFinished,
        MyWorkDeskSection.unlabeled => '',
      };
      final count = group.section == MyWorkDeskSection.needsYou
          ? myWorkNeedsYouObligationReceiptCount(
              group.cards,
              state.attentionByBeacon,
            )
          : null;
      final helper = group.section == MyWorkDeskSection.finished
          ? l10n.myWorkFinishedHint
          : null;
      slivers.add(
        SliverToBoxAdapter(
          child: TenturaSectionHeader(
            label: headerLabel,
            count: count,
            helperText: helper,
          ),
        ),
      );
    }
    slivers.add(
      SliverList.separated(
        itemCount: group.cards.length,
        separatorBuilder: (_, _) => SizedBox(height: tt.rowGap),
        itemBuilder: (context, index) {
          final vm = group.cards[index];
          final tile = _myWorkCardTile(context: context, vm: vm);
          // #487 — a child Request sits indented under its parent; past two
          // levels the "Part of: …" line carries the rest, so narrow
          // screens keep a usable card width.
          final depth = group.depthOf(vm.beaconId);
          if (depth == 0) return tile;
          return Padding(
            padding: EdgeInsetsDirectional.only(
              start: tt.screenHPadding * (depth > 2 ? 2 : depth),
            ),
            child: tile,
          );
        },
      ),
    );
  }
  // #269 — the archive is one tap away at the end of the list too, not only
  // through the filter menu or the empty state (same words as that
  // shortcut); hidden while nothing is archived or the archive is shown.
  if (state.filter != MyWorkFilter.archived && state.archivedCountHint > 0) {
    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: tt.rowGap),
          child: Center(
            child: TenturaTextAction(
              label: l10n.myWorkEmptyArchiveShortcut(state.archivedCountHint),
              onPressed: () =>
                  context.read<MyWorkCubit>().setFilter(MyWorkFilter.archived),
            ),
          ),
        ),
      ),
    );
  }
  slivers.add(
    SliverPadding(
      padding: EdgeInsets.only(bottom: tt.rowGap),
      sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
    ),
  );
  return slivers;
}

Widget _myWorkCardTile({
  required BuildContext context,
  required MyWorkCardViewModel vm,
}) {
  return BlocSelector<HomeAttentionCubit, HomeAttentionState, bool>(
    selector: (state) => state.isMyWorkBeaconMarked(vm.beaconId),
    builder: (_, attentionMarked) => MyWorkCardRouter(
      key: ValueKey('${vm.kind.name}-${vm.beaconId}'),
      vm: vm,
      attentionMarked: attentionMarked,
    ),
  );
}
