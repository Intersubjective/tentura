import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/inbox_style_app_bar.dart';

import '../bloc/my_work_cubit.dart';
import '../widget/my_work_cards.dart';

@RoutePage()
class MyWorkScreen extends StatelessWidget implements AutoRouteWrapper {
  const MyWorkScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) =>
      BlocSelector<AuthCubit, AuthState, String>(
        bloc: GetIt.I<AuthCubit>(),
        selector: (state) => state.currentAccountId,
        builder: (_, accountId) => BlocProvider(
          key: ValueKey(accountId),
          create: (_) => MyWorkCubit(),
          child: BlocListener<MyWorkCubit, MyWorkState>(
            listener: commonScreenBlocListener,
            child: this,
          ),
        ),
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
          ..setFilter(MyWorkFilter.all)
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
  MyWorkFilter.all => l10n.myWorkFilterAll,
  MyWorkFilter.authored => l10n.myWorkFilterAuthored,
  MyWorkFilter.committed => l10n.myWorkFilterCommitted,
  MyWorkFilter.archived => l10n.myWorkFilterArchived,
};

class _MyWorkFilterMenu extends StatelessWidget {
  const _MyWorkFilterMenu();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return BlocSelector<MyWorkCubit, MyWorkState, MyWorkFilter>(
      selector: (s) => s.filter,
      builder: (context, filter) {
        return PopupMenuButton<MyWorkFilter>(
          tooltip: l10n.myWorkFilterMenuTooltip,
          onSelected: (f) => context.read<MyWorkCubit>().setFilter(f),
          offset: const Offset(0, 40),
          itemBuilder: (context) => [
            for (final f in MyWorkFilter.values)
              PopupMenuItem<MyWorkFilter>(
                value: f,
                child: Text(_labelForFilter(l10n, f)),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
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

  String _emptyMessage(L10n l10n, MyWorkFilter f) => switch (f) {
    MyWorkFilter.all => l10n.myWorkEmptyAll,
    MyWorkFilter.authored => l10n.myWorkEmptyAuthored,
    MyWorkFilter.committed => l10n.myWorkEmptyCommitted,
    MyWorkFilter.archived => l10n.myWorkEmptyArchived,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final cubit = context.read<MyWorkCubit>();

    return BlocBuilder<MyWorkCubit, MyWorkState>(
      buildWhen: (p, c) =>
          p != c &&
          (c.isSuccess || c.isLoading || c.hasError || c.closedFetchInProgress),
      builder: (_, state) {
        if (state.isLoading) {
          return const Center(
            child: CircularProgressIndicator.adaptive(),
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
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.work_outline,
                  size: 64,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: kSpacingMedium),
                Text(
                  _emptyMessage(l10n, state.filter),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return RefreshIndicator.adaptive(
          onRefresh: cubit.fetch,
          child: ListView.separated(
            padding: kPaddingSmallV,
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
