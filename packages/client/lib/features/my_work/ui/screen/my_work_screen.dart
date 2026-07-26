import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';
import 'package:tentura/ui/widget/show_anchored_popup_menu.dart';

import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';

import '../bloc/my_work_cubit.dart';
import '../../domain/entity/my_work_card_view_model.dart';
import '../widget/my_work_beacon_view_pane.dart';
import '../widget/my_work_cards.dart';
import '../widget/my_work_empty_body.dart';
import '../widget/my_work_finished_status_row.dart';

@RoutePage()
class MyWorkScreen extends StatefulWidget implements AutoRouteWrapper {
  const MyWorkScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => this;

  @override
  State<MyWorkScreen> createState() => _MyWorkScreenState();
}

class _MyWorkScreenState extends State<MyWorkScreen> {
  String? _selectedBeaconId;
  String? _selectedViewTab;
  String? _selectedPeopleTabAttention;
  var _roomOpen = false;
  var _roomCloseNonce = 0;
  var _fitsFourColumns = false;
  var _fitsMasterDetail = true;

  void _selectCard(
    MyWorkCardViewModel vm, {
    String? viewTab,
    String? peopleTabAttention,
  }) {
    if (vm.kind == MyWorkCardKind.authoredDraft) return;
    setState(() {
      final nextId = vm.beaconId;
      if (_selectedBeaconId != nextId) {
        _roomOpen = false;
      }
      _selectedBeaconId = nextId;
      _selectedViewTab = viewTab;
      _selectedPeopleTabAttention = peopleTabAttention;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedBeaconId = null;
      _selectedViewTab = null;
      _selectedPeopleTabAttention = null;
      _roomOpen = false;
    });
  }

  void _onEmbeddedRoomOpenChanged(bool open) {
    if (_roomOpen == open) return;
    setState(() => _roomOpen = open);
  }

  void _onLayoutMetrics({
    required bool fitsFour,
    required bool fitsMasterDetail,
  }) {
    if (_fitsFourColumns == fitsFour && _fitsMasterDetail == fitsMasterDetail) {
      return;
    }
    setState(() {
      _fitsFourColumns = fitsFour;
      _fitsMasterDetail = fitsMasterDetail;
    });
  }

  void _backToList() {
    if (_roomOpen) {
      setState(() {
        _roomOpen = false;
        _roomCloseNonce++;
      });
      return;
    }
    setState(() {
      _selectedBeaconId = null;
      _selectedViewTab = null;
      _selectedPeopleTabAttention = null;
    });
  }

  bool get _showList {
    if (!_fitsMasterDetail) return _selectedBeaconId == null;
    return !(_roomOpen && !_fitsFourColumns);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final useExpandedPane = context.windowClass == WindowClass.expanded;
    final tt = context.tt;

    return BlocListener<HomeTabReselectCubit, HomeTabReselectState>(
      listenWhen: (prev, curr) =>
          prev.myWorkReselectCount != curr.myWorkReselectCount,
      listener: (context, _) {
        _clearSelection();
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
          title: useExpandedPane
              ? const SizedBox.shrink()
              : const Row(
                  children: [
                    Expanded(child: _MyWorkFilterMenu()),
                    _MyWorkSortButton(),
                  ],
                ),
          actions: useExpandedPane
              ? null
              : [
                  IconButton(
                    tooltip: l10n.newBeacon,
                    onPressed: () =>
                        context.read<ScreenCubit>().showBeaconCreate(),
                    icon: const Icon(Icons.add),
                  ),
                  const _MyWorkOverflowMenu(),
                ],
          row: useExpandedPane
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final masterWidth = deskMasterPaneWidth(
                      constraints.maxWidth,
                      context.tt,
                    );
                    final showList = _showList;
                    final useMasterWidth = showList && _fitsMasterDetail;
                    return Row(
                      children: [
                        if (showList)
                          useMasterWidth
                              ? SizedBox(
                                  width: masterWidth,
                                  child: const Row(
                                    children: [
                                      Expanded(child: _MyWorkFilterMenu()),
                                      _MyWorkSortButton(),
                                    ],
                                  ),
                                )
                              : const Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(child: _MyWorkFilterMenu()),
                                      _MyWorkSortButton(),
                                    ],
                                  ),
                                )
                        else
                          Semantics(
                            label: l10n.myWorkBackToList,
                            button: true,
                            child: IconButton(
                              tooltip: l10n.myWorkBackToList,
                              onPressed: _backToList,
                              icon: const Icon(Icons.arrow_back),
                            ),
                          ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: l10n.newBeacon,
                                  onPressed: () => context
                                      .read<ScreenCubit>()
                                      .showBeaconCreate(),
                                  icon: const Icon(Icons.add),
                                ),
                                const _MyWorkOverflowMenu(),
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
          child: _MyWorkBody(
            useExpandedPane: useExpandedPane,
            selectedBeaconId: _selectedBeaconId,
            selectedViewTab: _selectedViewTab,
            selectedPeopleTabAttention: _selectedPeopleTabAttention,
            showList: _showList,
            roomCloseNonce: _roomCloseNonce,
            onSelectCard: _selectCard,
            onEmbeddedLeave: _clearSelection,
            onEmbeddedRoomOpenChanged: _onEmbeddedRoomOpenChanged,
            onLayoutMetrics: _onLayoutMetrics,
          ),
        ),
      ),
    );
  }
}

class _MyWorkOverflowMenu extends StatelessWidget {
  const _MyWorkOverflowMenu();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: tt.buttonHeight,
        minHeight: tt.buttonHeight,
      ),
      onSelected: (value) {
        if (value == 'archive') {
          context.read<MyWorkCubit>().setFilter(MyWorkFilter.archived);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'archive',
          child: Text(l10n.myWorkOverflowArchive),
        ),
      ],
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

class _MyWorkFilterMenu extends StatelessWidget {
  const _MyWorkFilterMenu();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);

    return BlocSelector<MyWorkCubit, MyWorkState, MyWorkFilter>(
      selector: (s) => s.filter,
      builder: (context, filter) {
        final scheme = theme.colorScheme;
        final tt = context.tt;
        return Tooltip(
          message: l10n.myWorkFilterMenuTooltip,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: tt.tightGap * 2),
                minimumSize: Size(tt.buttonHeight, tt.buttonHeight),
                foregroundColor: scheme.onPrimary,
              ),
              onPressed: () => unawaited(_showMyWorkFilterMenu(context, l10n)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _labelForFilter(l10n, filter),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TenturaText.labelLarge(scheme.onPrimary).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    color: scheme.onPrimary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

MyWorkSort _myWorkSortAfter(MyWorkSort current) => switch (current) {
  MyWorkSort.recent => MyWorkSort.oldest,
  MyWorkSort.oldest => MyWorkSort.alphabetical,
  MyWorkSort.alphabetical => MyWorkSort.recent,
};

class _MyWorkSortButton extends StatefulWidget {
  const _MyWorkSortButton();

  @override
  State<_MyWorkSortButton> createState() => _MyWorkSortButtonState();
}

class _MyWorkSortButtonState extends State<_MyWorkSortButton> {
  static const _debounce = Duration(milliseconds: 220);

  DateTime? _lastTap;

  void _onPressed(MyWorkSort current) {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < _debounce) {
      return;
    }
    _lastTap = now;
    context.read<MyWorkCubit>().setSort(_myWorkSortAfter(current));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return BlocSelector<MyWorkCubit, MyWorkState, MyWorkSort>(
      selector: (s) => s.sort,
      builder: (context, sort) {
        final scheme = Theme.of(context).colorScheme;
        final tt = context.tt;
        final label = switch (sort) {
          MyWorkSort.recent => l10n.myWorkSortRecent,
          MyWorkSort.oldest => l10n.myWorkSortOldest,
          MyWorkSort.alphabetical => l10n.myWorkSortAlphabetical,
        };
        return Tooltip(
          message: l10n.myWorkSortMenuTooltip,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: tt.tightGap * 2),
              minimumSize: Size(tt.buttonHeight, tt.buttonHeight),
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

MyWorkCardViewModel? _selectedMyWorkCard(
  List<MyWorkCardViewModel> cards,
  String? selectedId, {
  bool allowDefaultToFirst = true,
}) {
  final viewable = cards
      .where((c) => c.kind != MyWorkCardKind.authoredDraft)
      .toList(growable: false);
  if (viewable.isEmpty) return null;
  if (selectedId != null) {
    for (final card in viewable) {
      if (card.beaconId == selectedId) {
        return card;
      }
    }
  }
  if (!allowDefaultToFirst) return null;
  return viewable.first;
}

class _MyWorkBody extends StatelessWidget {
  const _MyWorkBody({
    required this.useExpandedPane,
    required this.selectedBeaconId,
    required this.selectedViewTab,
    required this.selectedPeopleTabAttention,
    required this.showList,
    required this.roomCloseNonce,
    required this.onSelectCard,
    required this.onEmbeddedLeave,
    required this.onEmbeddedRoomOpenChanged,
    required this.onLayoutMetrics,
  });

  final bool useExpandedPane;
  final String? selectedBeaconId;
  final String? selectedViewTab;
  final String? selectedPeopleTabAttention;
  final bool showList;
  final int roomCloseNonce;
  final MyWorkCardSelect onSelectCard;
  final VoidCallback onEmbeddedLeave;
  final ValueChanged<bool> onEmbeddedRoomOpenChanged;
  final void Function({
    required bool fitsFour,
    required bool fitsMasterDetail,
  }) onLayoutMetrics;

  bool _shouldRebuild(MyWorkState p, MyWorkState c) {
    if (p.status != c.status ||
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
        p.archivedCountHint != c.archivedCountHint ||
        p.finishedArchiveHintDismissed != c.finishedArchiveHintDismissed) {
      return true;
    }
    if (p.nonArchivedCards != c.nonArchivedCards ||
        p.archivedCards != c.archivedCards) {
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
            useExpandedPane: useExpandedPane,
            selectedBeaconId: selectedBeaconId,
            onSelectCard: onSelectCard,
          );

          if (!useExpandedPane) {
            return TenturaContentColumn(child: listBody);
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final bodyWidth = constraints.maxWidth;
              final fitsMasterDetail = deskFitsMasterDetail(bodyWidth, tt);
              final fitsFour = myWorkFitsFourColumns(bodyWidth, tt);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onLayoutMetrics(
                  fitsFour: fitsFour,
                  fitsMasterDetail: fitsMasterDetail,
                );
              });

              if (!fitsMasterDetail) {
                if (selectedBeaconId == null) {
                  return listBody;
                }
                final swapSelected = _selectedMyWorkCard(
                  state.visibleCards,
                  selectedBeaconId,
                  allowDefaultToFirst: false,
                );
                return _MyWorkExpandedPreview(
                  selected: swapSelected,
                  viewTab: selectedViewTab,
                  peopleTabAttention: selectedPeopleTabAttention,
                  embeddedRoomCoVisible: false,
                  suppressEmbeddedRoomBack: true,
                  roomCloseNonce: roomCloseNonce,
                  onEmbeddedRoomOpenChanged: onEmbeddedRoomOpenChanged,
                  onEmbeddedLeave: onEmbeddedLeave,
                );
              }

              final masterWidth = deskMasterPaneWidth(bodyWidth, tt);
              final splitSelected = _selectedMyWorkCard(
                state.visibleCards,
                selectedBeaconId,
              );
              final children = <Widget>[
                if (showList) ...[
                  SizedBox(width: masterWidth, child: listBody),
                  SizedBox(width: tt.screenHPadding),
                  const TenturaVerticalHairline(),
                  SizedBox(width: tt.screenHPadding),
                ],
                Expanded(
                  child: _MyWorkExpandedPreview(
                    selected: splitSelected,
                    viewTab: splitSelected?.beaconId == selectedBeaconId
                        ? selectedViewTab
                        : null,
                    peopleTabAttention:
                        splitSelected?.beaconId == selectedBeaconId
                        ? selectedPeopleTabAttention
                        : null,
                    embeddedRoomCoVisible: fitsFour,
                    suppressEmbeddedRoomBack: !showList,
                    roomCloseNonce: roomCloseNonce,
                    onEmbeddedRoomOpenChanged: onEmbeddedRoomOpenChanged,
                    onEmbeddedLeave: onEmbeddedLeave,
                  ),
                ),
              ];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              );
            },
          );
        },
      ),
    );
  }
}

class _MyWorkExpandedPreview extends StatelessWidget {
  const _MyWorkExpandedPreview({
    required this.selected,
    required this.viewTab,
    required this.peopleTabAttention,
    required this.embeddedRoomCoVisible,
    required this.suppressEmbeddedRoomBack,
    required this.roomCloseNonce,
    required this.onEmbeddedRoomOpenChanged,
    required this.onEmbeddedLeave,
  });

  final MyWorkCardViewModel? selected;
  final String? viewTab;
  final String? peopleTabAttention;
  final bool embeddedRoomCoVisible;
  final bool suppressEmbeddedRoomBack;
  final int roomCloseNonce;
  final ValueChanged<bool> onEmbeddedRoomOpenChanged;
  final VoidCallback onEmbeddedLeave;

  @override
  Widget build(BuildContext context) {
    final selectedCard = selected;
    if (selectedCard == null) {
      final tt = context.tt;
      final l10n = L10n.of(context)!;
      return Center(
        child: Padding(
          padding: EdgeInsets.all(tt.screenHPadding),
          child: Text(
            l10n.myWorkEmptyActive,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return MyWorkBeaconViewPane(
      key: ValueKey(
        'my-work-bv-pane-${selectedCard.beaconId}:$viewTab:$peopleTabAttention',
      ),
      beaconId: selectedCard.beaconId,
      viewTab: viewTab,
      peopleTabAttention: peopleTabAttention,
      embeddedRoomCoVisible: embeddedRoomCoVisible,
      suppressEmbeddedRoomBack: suppressEmbeddedRoomBack,
      embeddedRoomCloseNonce: roomCloseNonce,
      onEmbeddedRoomOpenChanged: onEmbeddedRoomOpenChanged,
      onEmbeddedLeave: onEmbeddedLeave,
    );
  }
}

class _MyWorkListBody extends StatelessWidget {
  const _MyWorkListBody({
    required this.state,
    required this.cubit,
    required this.l10n,
    required this.tt,
    required this.useExpandedPane,
    required this.selectedBeaconId,
    required this.onSelectCard,
  });

  final MyWorkState state;
  final MyWorkCubit cubit;
  final L10n l10n;
  final TenturaTokens tt;
  final bool useExpandedPane;
  final String? selectedBeaconId;
  final MyWorkCardSelect onSelectCard;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator.adaptive(),
      );
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
    final showFinishedHint =
        !state.finishedArchiveHintDismissed &&
        (state.filter == MyWorkFilter.active ||
            state.filter == MyWorkFilter.all) &&
        cards.any((c) => c.isFinishedCard);
    if (cards.isEmpty) {
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
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
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
                        AutoTabsRouter.of(context).setActiveIndex(1),
                    onShowDrafts: () => cubit.setFilter(MyWorkFilter.drafts),
                    onShowArchived: () =>
                        cubit.setFilter(MyWorkFilter.archived),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    final onSelect = useExpandedPane ? onSelectCard : null;
    return RefreshIndicator.adaptive(
      onRefresh: cubit.fetch,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(vertical: tt.rowGap),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: cards.length + (showFinishedHint ? 1 : 0),
        separatorBuilder: (_, _) => SizedBox(height: tt.rowGap),
        itemBuilder: (_, i) {
          if (showFinishedHint && i == 0) {
            return MyWorkFinishedArchiveHint(
              onDismiss: cubit.dismissFinishedArchiveHint,
            );
          }
          final cardIndex = showFinishedHint ? i - 1 : i;
          final vm = cards[cardIndex];
          return BlocSelector<HomeAttentionCubit, HomeAttentionState, bool>(
            selector: (state) => state.isMyWorkBeaconMarked(vm.beaconId),
            builder: (_, attentionMarked) => MyWorkCardRouter(
              key: ValueKey('${vm.kind.name}-${vm.beaconId}'),
              vm: vm,
              attentionMarked: attentionMarked,
              isSelected: onSelect != null && vm.beaconId == selectedBeaconId,
              onSelect: onSelect,
            ),
          );
        },
      ),
    );
  }
}
