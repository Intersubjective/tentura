import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/context/ui/widget/context_drop_down.dart';

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
              context.read<RatingCubit>().fetch(state.selected),
        ),
        const BlocListener<RatingCubit, RatingState>(
          listener: commonScreenBlocListener,
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
          p.isSortedByClass != c.isSortedByClass,
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final filter = state.searchFilter;
        final items = filter.isEmpty
            ? state.items
            : state.items
                  .where(
                    (e) => e.title.toLowerCase().contains(filter.toLowerCase()),
                  )
                  .toList();

        return Scaffold(
          appBar: AppBar(
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
                  padding: EdgeInsets.zero,
                  alignment: Alignment.center,
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
                        padding: const EdgeInsets.only(right: kSpacingLarge),
                        child: Text(l10n.rating),
                      ),
                      Expanded(
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
                    ],
                  ),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(48),
              child: Padding(
                padding: kPaddingH,
                child: ContextDropDown(key: Key('RatingContextSelector')),
              ),
            ),
          ),
          body: _isScatterView
              ? RatingScatterView(profiles: items)
              : Column(
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
                      child: ListView.separated(
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
                  ],
                ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return SizedBox(
      height: 48,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          kSpacingMedium,
          kSpacingSmall,
          kSpacingMedium,
          kSpacingSmall,
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
              child: InkWell(
                onTap: cubit.sortByAlterColumn,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        l10n.alter,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSortedByAlter)
                      Icon(
                        isSortedByAsc
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: kSpacingSmall),
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: cubit.sortByDirectColumn,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        l10n.iTrustThem,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isSortedByReverse && !isSortedByAlter && !isSortedByClass)
                      Icon(
                        isSortedByAsc
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: kSpacingSmall),
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: cubit.sortByReverseColumn,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        l10n.theyTrustMe,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSortedByReverse && !isSortedByAlter && !isSortedByClass)
                      Icon(
                        isSortedByAsc
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: kSpacingSmall),
            SizedBox(
              width: 100,
              child: InkWell(
                onTap: cubit.sortByClassColumn,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        l10n.classLabel,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSortedByClass)
                      Icon(
                        isSortedByAsc
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
