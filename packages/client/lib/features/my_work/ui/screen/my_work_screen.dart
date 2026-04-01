import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_tile.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/context/ui/widget/context_drop_down.dart';

import '../bloc/my_work_cubit.dart';

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
          create: (_) => MyWorkCubit(
            initialContext: context.read<ContextCubit>().state.selected,
          ),
          child: MultiBlocListener(
            listeners: [
              BlocListener<ContextCubit, ContextState>(
                listenWhen: (p, c) => p.selected != c.selected,
                listener: (context, state) =>
                    context.read<MyWorkCubit>().fetch(state.selected),
              ),
              const BlocListener<MyWorkCubit, MyWorkState>(
                listener: commonScreenBlocListener,
              ),
            ],
            child: this,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final cubit = context.read<MyWorkCubit>();
    return SafeArea(
      minimum: kPaddingSmallH,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ContextDropDown(),

          // Active / Closed
          BlocSelector<MyWorkCubit, MyWorkState, MyWorkSection>(
            selector: (state) => state.section,
            builder: (_, section) => Padding(
              padding: kPaddingSmallV,
              child: Wrap(
                spacing: kSpacingSmall,
                children: [
                  ChoiceChip(
                    selected: section == MyWorkSection.active,
                    label: Text(l10n.myWorkSectionActive),
                    onSelected: (_) =>
                        cubit.setSection(MyWorkSection.active),
                  ),
                  ChoiceChip(
                    selected: section == MyWorkSection.closed,
                    label: Text(l10n.myWorkSectionClosed),
                    onSelected: (_) =>
                        cubit.setSection(MyWorkSection.closed),
                  ),
                ],
              ),
            ),
          ),

          // Filter chips
          BlocSelector<MyWorkCubit, MyWorkState, MyWorkFilter>(
            selector: (state) => state.filter,
            builder: (_, filter) => Padding(
              padding: kPaddingSmallV,
              child: Wrap(
                spacing: kSpacingSmall,
                children: [
                  for (final f in MyWorkFilter.values)
                    ChoiceChip(
                      selected: filter == f,
                      label: Text(
                        switch (f) {
                          MyWorkFilter.all => l10n.myWorkFilterAll,
                          MyWorkFilter.authored => l10n.myWorkFilterAuthored,
                          MyWorkFilter.committed => l10n.myWorkFilterCommitted,
                        },
                      ),
                      onSelected: (_) => cubit.setFilter(f),
                    ),
                ],
              ),
            ),
          ),

          // Beacons list
          Expanded(
            child: BlocBuilder<MyWorkCubit, MyWorkState>(
              buildWhen: (_, c) =>
                  c.isSuccess || c.isLoading || c.hasError,
              builder: (_, state) {
                if (state.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }
                final beacons = state.visibleBeacons;
                if (beacons.isEmpty) {
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
                          state.section == MyWorkSection.active
                              ? l10n.myWorkEmptyActive
                              : l10n.myWorkEmptyClosed,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator.adaptive(
                  onRefresh: () => Future.wait([
                    cubit.fetch(),
                    context.read<ContextCubit>().fetch(fromCache: false),
                  ]),
                  child: ListView.builder(
                    itemCount: beacons.length,
                    itemBuilder: (_, i) {
                      final beacon = beacons[i];
                      return Padding(
                        padding: kPaddingSmallV,
                        child: BeaconTile(
                          key: ValueKey(beacon),
                          beacon: beacon,
                          isMine: state.filter != MyWorkFilter.committed,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
