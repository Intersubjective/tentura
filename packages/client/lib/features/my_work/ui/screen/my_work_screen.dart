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

/// Left-to-right tab order (must stay in sync with [TabController] length).
const _kSectionTabOrder = <MyWorkSection>[
  MyWorkSection.active,
  MyWorkSection.review,
  MyWorkSection.closed,
  MyWorkSection.drafts,
];

int _indexForSection(MyWorkSection s) => _kSectionTabOrder.indexOf(s);

MyWorkSection _sectionAtIndex(int i) => _kSectionTabOrder[i];

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
    return const SafeArea(
      minimum: kPaddingSmallH,
      child: _MyWorkBody(),
    );
  }
}

class _MyWorkBody extends StatefulWidget {
  const _MyWorkBody();

  @override
  State<_MyWorkBody> createState() => _MyWorkBodyState();
}

class _MyWorkBodyState extends State<_MyWorkBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final section = context.read<MyWorkCubit>().state.section;
    _tabController = TabController(
      length: _kSectionTabOrder.length,
      vsync: this,
      initialIndex: _indexForSection(section),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final cubit = context.read<MyWorkCubit>();

    return BlocListener<MyWorkCubit, MyWorkState>(
      listenWhen: (p, c) => p.section != c.section,
      listener: (context, state) {
        final idx = _indexForSection(state.section);
        if (_tabController.index != idx) {
          _tabController.animateTo(idx);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ContextDropDown(),

          // Active / Review / Closed / Drafts
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
                _,
                draftsCount,
                activeCount,
                reviewCount,
                closedCount,
              ) = data;
              return Padding(
                padding: kPaddingSmallV,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  automaticIndicatorColorAdjustment: false,
                  labelColor: theme.colorScheme.primary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  indicatorColor: theme.colorScheme.primary,
                  dividerColor: theme.colorScheme.outlineVariant,
                  onTap: (i) => cubit.setSection(_sectionAtIndex(i)),
                  tabs: [
                    Tab(
                      child: _MyWorkSectionTabLabel(
                        title: l10n.myWorkSectionActive,
                        count: activeCount,
                      ),
                    ),
                    Tab(
                      child: _MyWorkSectionTabLabel(
                        title: l10n.myWorkSectionReview,
                        count: reviewCount,
                      ),
                    ),
                    Tab(
                      child: _MyWorkSectionTabLabel(
                        title: l10n.myWorkSectionClosed,
                        count: closedCount,
                      ),
                    ),
                    Tab(
                      child: _MyWorkSectionTabLabel(
                        title: l10n.myWorkSectionDrafts,
                        count: draftsCount,
                      ),
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

class _MyWorkSectionTabLabel extends StatelessWidget {
  const _MyWorkSectionTabLabel({
    required this.title,
    required this.count,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final semanticsLabel = count > 0 ? '$title, $count items' : title;
    return Semantics(
      label: semanticsLabel,
      child: Builder(
        builder: (context) {
          final baseStyle = DefaultTextStyle.of(context).style;
          final baseColor = baseStyle.color;
          final countColor = baseColor?.withValues(alpha: 0.85) ?? baseColor;
          return Text.rich(
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
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
          );
        },
      ),
    );
  }
}
