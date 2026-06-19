import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/inbox_style_app_bar.dart';
import 'package:tentura/ui/widget/show_anchored_popup_menu.dart';

import '../bloc/my_work_cubit.dart';
import '../widget/my_work_cards.dart';
import '../widget/my_work_empty_body.dart';
import '../widget/my_work_new_stuff_reporter.dart';

@RoutePage()
class MyWorkScreen extends StatelessWidget implements AutoRouteWrapper {
  const MyWorkScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) =>
      BlocSelector<AuthCubit, AuthState, String>(
        bloc: GetIt.I<AuthCubit>(),
        selector: (state) => state.currentAccountId,
        builder: (_, accountId) {
          if (accountId.isEmpty) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator.adaptive(),
              ),
            );
          }
          return BlocProvider(
            key: ValueKey(accountId),
            create: (_) => MyWorkCubit(userId: accountId),
            child: MultiBlocListener(
              listeners: const [
                BlocListener<MyWorkCubit, MyWorkState>(
                  listener: commonScreenBlocListener,
                ),
              ],
              child: MyWorkNewStuffReporter(child: this),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
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
        appBar: InboxStyleAppBar(
          title: const Row(
            children: [
              Expanded(child: _MyWorkFilterMenu()),
              _MyWorkSortButton(),
            ],
          ),
          actions: [
            IconButton(
              tooltip: l10n.newBeacon,
              onPressed: () => context.read<ScreenCubit>().showBeaconCreate(),
              icon: const Icon(Icons.add),
            ),
            const _MyWorkOverflowMenu(),
          ],
        ),
        body: const SafeArea(
          minimum: kPaddingSmallH,
          child: _MyWorkBody(),
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

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
        return Tooltip(
          message: l10n.myWorkFilterMenuTooltip,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: scheme.onPrimary,
              ),
              onPressed: () =>
                  unawaited(_showMyWorkFilterMenu(context, l10n)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _labelForFilter(l10n, filter),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onPrimary,
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
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;

    return BlocSelector<MyWorkCubit, MyWorkState, MyWorkSort>(
      selector: (s) => s.sort,
      builder: (context, sort) {
        final scheme = theme.colorScheme;
        final label = switch (sort) {
          MyWorkSort.recent => l10n.myWorkSortRecent,
          MyWorkSort.oldest => l10n.myWorkSortOldest,
          MyWorkSort.alphabetical => l10n.myWorkSortAlphabetical,
        };
        return TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: scheme.onPrimary,
          ),
          onPressed: () => _onPressed(sort),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 88),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.swap_vert,
                size: 20,
                color: scheme.onPrimary,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MyWorkBody extends StatelessWidget {
  const _MyWorkBody();

  bool _shouldRebuild(MyWorkState p, MyWorkState c) {
    if (p.status != c.status ||
        p.filter != c.filter ||
        p.sort != c.sort ||
        p.closedFetchInProgress != c.closedFetchInProgress ||
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
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final cubit = context.read<MyWorkCubit>();

    return BlocBuilder<MyWorkCubit, MyWorkState>(
      buildWhen: _shouldRebuild,
      builder: (_, state) {
        if (state.isLoading) {
          return const Center(
            child: CircularProgressIndicator.adaptive(),
          );
        }
        if (state.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: kSpacingMedium),
                FilledButton(
                  onPressed: cubit.fetch,
                  child: Text(l10n.myWorkRetry),
                ),
              ],
            ),
          );
        }
        if (state.filter == MyWorkFilter.archived &&
            !state.closedDataFetched &&
            state.closedFetchInProgress) {
          return const Center(
            child: CircularProgressIndicator.adaptive(),
          );
        }
        final cards = state.visibleCards;
        if (cards.isEmpty) {
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
                    onCreateBeacon: () =>
                        context.read<ScreenCubit>().showBeaconCreate(),
                    onOpenInbox: () =>
                        AutoTabsRouter.of(context).setActiveIndex(1),
                    onShowDrafts: () =>
                        cubit.setFilter(MyWorkFilter.drafts),
                    onShowArchived: () =>
                        cubit.setFilter(MyWorkFilter.archived),
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator.adaptive(
          onRefresh: cubit.fetch,
          child: ListView.separated(
            padding: kPaddingSmallV,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: kSpacingSmall),
            itemBuilder: (_, i) {
              final vm = cards[i];
              return MyWorkCardRouter(
                key: ValueKey('${vm.kind.name}-${vm.beaconId}'),
                vm: vm,
              );
            },
          ),
        );
      },
    );
  }
}
