import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import 'package:tentura/consts.dart';

import 'package:tentura/features/context/ui/bloc/context_cubit.dart';

import '../bloc/rating_cubit.dart';
import '../widget/rating_list_tile.dart';
import '../widget/rating_scatter_view.dart';

@RoutePage()
class RatingScreen extends StatefulWidget implements AutoRouteWrapper {
  const RatingScreen({super.key});

  @override
  State<RatingScreen> createState() => _RatingScreenState();

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => RatingCubit(),
      ),
      BlocProvider(
        create: (_) => ContextCubit(),
      ),
    ],
    child: MultiBlocListener(
      listeners: [
        BlocListener<ContextCubit, ContextState>(
          listenWhen: (p, c) => p.selected != c.selected,
          listener: (context, state) =>
              context.read<RatingCubit>().setContext(state.selected),
        ),
      ],
      child: this,
    ),
  );
}

class _RatingScreenState extends State<RatingScreen> {
  bool _isScatterView = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<RatingCubit>();
    return BlocBuilder<RatingCubit, RatingState>(
      buildWhen: (p, c) =>
          c.isSuccess ||
          c.isLoading ||
          p.isSortedByAsc != c.isSortedByAsc ||
          p.isSortedByReverse != c.isSortedByReverse ||
          p.isSortedByAlter != c.isSortedByAlter ||
          p.isSortedByClass != c.isSortedByClass ||
          p.searchFilter != c.searchFilter,
      builder: (context, state) {
        final tt = context.tt;
        final filter = state.searchFilter;
        final items = filter.isEmpty
            ? state.items
            : state.items
                  .where(
                    (e) =>
                        e.shownName.toLowerCase().contains(
                          filter.toLowerCase(),
                        ) ||
                        e.displayName.toLowerCase().contains(
                          filter.toLowerCase(),
                        ),
                  )
                  .toList();
        final isInitialLoading = state.isLoading && state.items.isEmpty;

        late final Widget body;
        if (isInitialLoading) {
          body = const Center(child: CircularProgressIndicator.adaptive());
        } else if (_isScatterView) {
          body = RatingScatterView(profiles: items);
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RatingHeatmapHeader(
                l10n: l10n,
                cubit: cubit,
                isSortedByReverse: state.isSortedByReverse,
                isSortedByAsc: state.isSortedByAsc,
                isSortedByAlter: state.isSortedByAlter,
                isSortedByClass: state.isSortedByClass,
              ),
              Expanded(
                child: items.isEmpty && filter.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: tt.cardPadding,
                          child: Text(
                            l10n.labelNothingHere,
                            textAlign: TextAlign.center,
                            style: TenturaText.bodyMedium(
                              Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : RefreshIndicator.adaptive(
                        onRefresh: cubit.fetch,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final profile = items[i];
                            return RatingListTile(
                              key: ValueKey(profile.id),
                              profile: profile,
                            );
                          },
                          padding: kPaddingH + kPaddingT,
                          separatorBuilder: separatorBuilder,
                        ),
                      ),
              ),
            ],
          );
        }

        return Scaffold(
          appBar: AppBar(
            leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
            actions: [
              // Toggle list / scatter view
              IconButton(
                tooltip: _isScatterView ? l10n.rating : l10n.scatterView,
                onPressed: () =>
                    setState(() => _isScatterView = !_isScatterView),
                icon: Icon(
                  _isScatterView ? Icons.list_rounded : Icons.scatter_plot,
                ),
              ),
              if (!_isScatterView)
                IconButton(
                  tooltip: l10n.buttonClose,
                  icon: const Icon(Icons.clear_rounded),
                  onPressed:
                      filter.isEmpty ? null : cubit.clearSearchFilter,
                ),
            ],
            title: _isScatterView
                ? Text(l10n.rating)
                : Row(
                    children: [
                      Padding(
                        padding: EdgeInsets.only(right: tt.sectionGap),
                        child: Text(l10n.rating),
                      ),
                      Expanded(
                        child: Semantics(
                          label: l10n.searchBy,
                          child: TextFormField(
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.zero,
                              hintText: l10n.searchBy,
                              isCollapsed: true,
                              isDense: true,
                            ),
                            initialValue: state.searchFilter,
                            onChanged: cubit.setSearchFilter,
                            textInputAction: TextInputAction.go,
                          ),
                        ),
                      ),
                    ],
                  ),
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(
                state.isLoading && state.items.isNotEmpty
                    ? tt.appBarHeight + tt.tightGap
                    : tt.appBarHeight,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.isLoading && state.items.isNotEmpty)
                    SizedBox(
                      height: tt.tightGap,
                      child: const LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
          body: SafeArea(child: body),
        );
      },
    );
  }
}

class _RatingHeatmapHeader extends StatelessWidget {
  const _RatingHeatmapHeader({
    required this.l10n,
    required this.cubit,
    required this.isSortedByReverse,
    required this.isSortedByAsc,
    required this.isSortedByAlter,
    required this.isSortedByClass,
  });

  final L10n l10n;
  final RatingCubit cubit;
  final bool isSortedByReverse;
  final bool isSortedByAsc;
  final bool isSortedByAlter;
  final bool isSortedByClass;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final colorScheme = Theme.of(context).colorScheme;
    final headerLabelStyle = TenturaText.titleSmall(
      colorScheme.onSurfaceVariant,
    ).copyWith(fontWeight: FontWeight.w600);
    return SizedBox(
      height: tt.buttonHeight,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          tt.screenHPadding,
          tt.tightGap,
          tt.screenHPadding,
          tt.tightGap,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          border: Border(
            bottom: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: _RatingSortHeader(
                label: l10n.alter,
                isActive: isSortedByAlter,
                isAscending: isSortedByAsc,
                labelStyle: headerLabelStyle,
                onTap: cubit.sortByAlterColumn,
              ),
            ),
            SizedBox(width: tt.tightGap),
            Expanded(
              flex: 2,
              child: _RatingSortHeader(
                label: l10n.iTrustThem,
                isActive:
                    !isSortedByReverse && !isSortedByAlter && !isSortedByClass,
                isAscending: isSortedByAsc,
                labelStyle: headerLabelStyle,
                alignment: Alignment.centerRight,
                onTap: cubit.sortByDirectColumn,
              ),
            ),
            SizedBox(width: tt.tightGap),
            Expanded(
              flex: 2,
              child: _RatingSortHeader(
                label: l10n.theyTrustMe,
                isActive: isSortedByReverse && !isSortedByAlter && !isSortedByClass,
                isAscending: isSortedByAsc,
                labelStyle: headerLabelStyle,
                alignment: Alignment.centerRight,
                onTap: cubit.sortByReverseColumn,
              ),
            ),
            SizedBox(width: tt.tightGap),
            SizedBox(
              width: 100,
              child: _RatingSortHeader(
                label: l10n.classLabel,
                isActive: isSortedByClass,
                isAscending: isSortedByAsc,
                labelStyle: headerLabelStyle,
                alignment: Alignment.center,
                onTap: cubit.sortByClassColumn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingSortHeader extends StatelessWidget {
  const _RatingSortHeader({
    required this.label,
    required this.isActive,
    required this.isAscending,
    required this.labelStyle,
    required this.onTap,
    this.alignment = Alignment.centerLeft,
  });

  final String label;
  final bool isActive;
  final bool isAscending;
  final TextStyle labelStyle;
  final VoidCallback onTap;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          child: Align(
            alignment: alignment,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: labelStyle,
                    textAlign: alignment == Alignment.center
                        ? TextAlign.center
                        : TextAlign.start,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive)
                  Icon(
                    isAscending
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: tt.iconSize,
                    color: colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
