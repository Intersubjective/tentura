import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widgets/app_choice_chip_style.dart';

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

          // Drafts / Active / Review / Closed
          BlocSelector<
              MyWorkCubit,
              MyWorkState,
              (MyWorkSection, int, int, int, int)>(
            selector: (state) => (
              state.section,
              state.countForSection(MyWorkSection.drafts),
              state.countForSection(MyWorkSection.active),
              state.countForSection(MyWorkSection.review),
              state.countForSection(MyWorkSection.closed),
            ),
            builder: (_, data) {
              final (
                section,
                draftsCount,
                activeCount,
                reviewCount,
                closedCount,
              ) = data;
              final chipStyle = AppChoiceChipStyle(theme.colorScheme);
              return Padding(
                padding: kPaddingSmallV,
                child: Wrap(
                  spacing: kSpacingSmall,
                  runSpacing: kSpacingSmall,
                  children: [
                    _MyWorkSectionChip(
                      chipStyle: chipStyle,
                      title: l10n.myWorkSectionDrafts,
                      count: draftsCount,
                      selected: section == MyWorkSection.drafts,
                      onSelected: () =>
                          cubit.setSection(MyWorkSection.drafts),
                    ),
                    _MyWorkSectionChip(
                      chipStyle: chipStyle,
                      title: l10n.myWorkSectionActive,
                      count: activeCount,
                      selected: section == MyWorkSection.active,
                      onSelected: () =>
                          cubit.setSection(MyWorkSection.active),
                    ),
                    _MyWorkSectionChip(
                      chipStyle: chipStyle,
                      title: l10n.myWorkSectionReview,
                      count: reviewCount,
                      selected: section == MyWorkSection.review,
                      onSelected: () =>
                          cubit.setSection(MyWorkSection.review),
                    ),
                    _MyWorkSectionChip(
                      chipStyle: chipStyle,
                      title: l10n.myWorkSectionClosed,
                      count: closedCount,
                      selected: section == MyWorkSection.closed,
                      onSelected: () =>
                          cubit.setSection(MyWorkSection.closed),
                    ),
                  ],
                ),
              );
            },
          ),

          // Filter chips (hidden on Drafts — that tab always shows merged list)
          BlocSelector<
              MyWorkCubit,
              MyWorkState,
              (MyWorkSection, MyWorkFilter)>(
            selector: (state) => (state.section, state.filter),
            builder: (_, data) {
              final (section, filter) = data;
              if (section == MyWorkSection.drafts) {
                return const SizedBox.shrink();
              }
              final chipStyle = AppChoiceChipStyle(theme.colorScheme);
              return Padding(
                padding: kPaddingSmallV,
                child: Wrap(
                  spacing: kSpacingSmall,
                  children: [
                    for (final f in MyWorkFilter.values)
                      ChoiceChip(
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
                          },
                        ),
                        onSelected: (_) => cubit.setFilter(f),
                      ),
                  ],
                ),
              );
            },
          ),

          // Beacons list
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
                if (state.section == MyWorkSection.closed &&
                    !state.closedDataFetched &&
                    state.closedFetchInProgress) {
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
                          switch (state.section) {
                            MyWorkSection.drafts => l10n.myWorkEmptyDrafts,
                            MyWorkSection.active => l10n.myWorkEmptyActive,
                            MyWorkSection.review => l10n.myWorkEmptyReview,
                            MyWorkSection.closed => l10n.myWorkEmptyClosed,
                          },
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
                          isMine: state.tileIsMine(beacon),
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

class _MyWorkSectionChip extends StatelessWidget {
  const _MyWorkSectionChip({
    required this.chipStyle,
    required this.title,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  final AppChoiceChipStyle chipStyle;
  final String title;
  final int count;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semanticsLabel =
        count > 0 ? '$title, $count items' : title;
    return ChoiceChip(
      color: chipStyle.background,
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: chipStyle.labelForeground,
      ),
      checkmarkColor: chipStyle.checkmarkColor,
      side: chipStyle.outline,
      selected: selected,
      label: Builder(
        builder: (context) {
          final baseStyle = DefaultTextStyle.of(context).style;
          final countColor =
              chipStyle.counterForeground(chipSelected: selected);
          return Semantics(
            label: semanticsLabel,
            child: Text.rich(
              TextSpan(
                style: baseStyle,
                children: [
                  TextSpan(text: title),
                  if (count > 0)
                    TextSpan(
                      text: ' $count',
                      style: baseStyle.copyWith(
                        fontSize: (baseStyle.fontSize ?? 14) * 0.92,
                        color: countColor,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      onSelected: (_) => onSelected(),
    );
  }
}
