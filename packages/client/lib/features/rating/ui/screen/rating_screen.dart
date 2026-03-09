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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return BlocBuilder<RatingCubit, RatingState>(
      buildWhen: (p, c) => c.isSuccess || c.isLoading,
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
              if (!_isScatterView) ...[
                // Clear input
                IconButton(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.center,
                  icon: const Icon(Icons.clear_rounded),
                  onPressed:
                      filter.isEmpty ? null : cubit.clearSearchFilter,
                ),
                // Toggle sorting by value
                IconButton(
                  onPressed: cubit.toggleSortingByAsc,
                  icon: state.isSortedByAsc
                      ? const Icon(Icons.keyboard_arrow_up_rounded)
                      : const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                // Toggle sorting by ego
                IconButton(
                  onPressed: cubit.toggleSortingByEgo,
                  icon: state.isSortedByEgo
                      ? const Icon(Icons.keyboard_arrow_right_rounded)
                      : const Icon(Icons.keyboard_arrow_left_rounded),
                ),
              ],
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
              : ListView.separated(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final profile = items[i];
                    return RatingListTile(
                      key: ValueKey(profile),
                      isDarkMode: isDarkMode,
                      profile: profile,
                    );
                  },
                  padding: kPaddingH + kPaddingT,
                  separatorBuilder: separatorBuilder,
                ),
        );
      },
    );
  }
}
