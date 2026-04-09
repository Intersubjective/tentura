import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widgets/app_choice_chip_style.dart';

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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
          onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
        ),
        title: Text(l10n.myWork),
        actions: [
          BlocBuilder<ProfileCubit, ProfileState>(
            bloc: GetIt.I<ProfileCubit>(),
            builder: (context, ps) {
              final p = ps.profile;
              return IconButton(
                tooltip: l10n.profile,
                onPressed: () => AutoTabsRouter.of(context).setActiveIndex(3),
                icon: p.hasAvatar
                    ? CircleAvatar(
                        backgroundImage: NetworkImage(p.avatarUrl),
                      )
                    : CircleAvatar(
                        child: Text(
                          p.title.isNotEmpty
                              ? p.title.substring(0, 1).toUpperCase()
                              : '?',
                        ),
                      ),
              );
            },
          ),
        ],
      ),
      body: const SafeArea(
        minimum: kPaddingSmallH,
        child: _MyWorkBody(),
      ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlocSelector<MyWorkCubit, MyWorkState, MyWorkFilter>(
          selector: (s) => s.filter,
          builder: (_, filter) {
            final chipStyle = AppChoiceChipStyle(theme.colorScheme);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: kPaddingSmallH.add(kPaddingSmallV),
              child: Row(
                children: [
                  for (final f in MyWorkFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: kSpacingSmall),
                      child: ChoiceChip(
                        color: chipStyle.background,
                        labelStyle: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: chipStyle.labelForeground,
                        ),
                        checkmarkColor: chipStyle.checkmarkColor,
                        side: chipStyle.outline,
                        selected: filter == f,
                        label: Text(
                          switch (f) {
                            MyWorkFilter.all => l10n.myWorkFilterAll,
                            MyWorkFilter.authored => l10n.myWorkFilterAuthored,
                            MyWorkFilter.committed =>
                              l10n.myWorkFilterCommitted,
                            MyWorkFilter.archived => l10n.myWorkFilterArchived,
                          },
                        ),
                        onSelected: (_) => cubit.setFilter(f),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: BlocBuilder<MyWorkCubit, MyWorkState>(
            buildWhen: (p, c) =>
                p != c &&
                (c.isSuccess ||
                    c.isLoading ||
                    c.hasError ||
                    c.closedFetchInProgress),
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
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: kSpacingSmall),
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
          ),
        ),
      ],
    );
  }
}
