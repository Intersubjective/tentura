import 'package:flutter/material.dart';

import 'package:tentura/app/platform/text_input_focus.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/ui/widget/tentura_info_hint_button.dart';

import 'package:tentura/consts.dart';

import 'package:tentura/features/context/ui/bloc/context_cubit.dart';

import '../bloc/rating_cubit.dart';
import '../widget/rating_list_tile.dart';
import '../widget/rating_scatter_view.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';

/// Lets a widget test say whether the browser focus is still on the search
/// field; null asks the platform.
@visibleForTesting
bool Function()? debugRatingSearchTextInputHasPlatformFocus;

/// Lets a widget test see which semantics identifier prefixes the screen
/// asks the browser to keep the field's focus on; null asks the platform.
@visibleForTesting
void Function(Iterable<String> prefixes)? debugRatingKeepTextInputFocusOnPress;

@RoutePage()
class RatingScreen extends StatefulWidget implements AutoRouteWrapper {
  const RatingScreen({super.key});

  /// Plain-tap explanation of the two rank columns (#261).
  static const columnsInfoKey = Key('RatingScreen.columnsInfo');

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

  /// Controlled by the cubit's search filter, so a clear empties the field
  /// (an `initialValue` kept the stale text, #603).
  late final _searchController = TextEditingController(
    text: context.read<RatingCubit>().state.searchFilter,
  );

  /// Close hands the caret back to the field, so the next keys land there
  /// (on web the first click after Close was lost, #603).
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // With semantics on, a press on ✕ moved the browser focus off the
    // field's input to the page, while Flutter still counted the field as
    // focused, so the first click back on it and the keys after it were lost
    // (#603, as #688). Cancelling the press keeps the browser focus on it.
    (debugRatingKeepTextInputFocusOnPress ?? keepTextInputFocusOnPress)(
      const [TestIds.ratingSearchClear],
    );
  }

  /// Keeps the caret and the keys in the search field. If Flutter counts the
  /// field as focused but the browser focus has left its input anyway, the
  /// field is re-attached the way a fresh click into it does (#603).
  void _keepSearchFocus() {
    if (!_searchFocusNode.hasFocus) {
      _searchFocusNode.requestFocus();
      return;
    }
    final hasPlatformFocus =
        (debugRatingSearchTextInputHasPlatformFocus ??
        textInputHasPlatformFocus)();
    if (hasPlatformFocus) return;
    _searchFocusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_searchFocusNode.hasFocus) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<RatingCubit>();
    return BlocListener<RatingCubit, RatingState>(
      listenWhen: (p, c) => p.searchFilter != c.searchFilter,
      listener: (_, state) {
        if (_searchController.text != state.searchFilter) {
          _searchController.text = state.searchFilter;
        }
      },
      child: _buildBody(l10n, cubit),
    );
  }

  Widget _buildBody(L10n l10n, RatingCubit cubit) {
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

        return HomeRailFrame(
          selectedTab: HomeTab.network,
          child: Scaffold(
            appBar: TenturaTopBar.of(
              context,
              alignment: TenturaTopBarAlignment.fullWidth,
              leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
              actions: [
                // The column headers' tooltips need a long-press on touch;
                // this explains both numbers with a plain tap (#261).
                TenturaInfoHintButton(
                  key: RatingScreen.columnsInfoKey,
                  fullText:
                      '${l10n.rankFromYou}: ${l10n.rankFromYouHint}\n\n'
                      '${l10n.rankToYou}: ${l10n.rankToYouHint}',
                  semanticsLabel: l10n.ratingColumnsInfoLabel,
                ),
                // Toggle list / scatter view
                IconButton(
                  tooltip: _isScatterView ? l10n.rating : l10n.scatterView,
                  onPressed: () =>
                      setState(() => _isScatterView = !_isScatterView),
                  icon: Icon(
                    _isScatterView ? Icons.list_rounded : Icons.scatter_plot,
                  ),
                ),
                // Only offer the clear button when there is something to clear,
                // so no disabled ✕ sits beside the working back arrow.
                // A click here counts as inside the field (no tap-outside
                // unfocus) and focus stays in it, so typing goes on (#603).
                if (!_isScatterView && filter.isNotEmpty)
                  TextFieldTapRegion(
                    child: Semantics(
                      container: true,
                      identifier: TestIds.ratingSearchClear,
                      child: IconButton(
                        tooltip: l10n.buttonClose,
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          cubit.clearSearchFilter();
                          _keepSearchFocus();
                          // The clear takes the ✕ out of the tree on the
                          // next frame, and the browser focus can leave the
                          // field's input then, after the check above passed
                          // (QA 7.50.7). Look again once that frame is drawn.
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _keepSearchFocus();
                          });
                        },
                      ),
                    ),
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
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              onChanged: cubit.setSearchFilter,
                              // A click on the field while the browser focus
                              // sits elsewhere puts it back on the input.
                              onTap: () {
                                if (_searchFocusNode.hasFocus) {
                                  _keepSearchFocus();
                                }
                              },
                              textInputAction: TextInputAction.go,
                            ),
                          ),
                        ),
                      ],
                    ),
              progress: TenturaTopBar.loadingBar(
                context,
                state.isLoading && state.items.isNotEmpty,
              ),
            ),
            body: SafeArea(
              child: _isScatterView ? body : TenturaContentColumn(child: body),
            ),
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
    final tt = context.tt;
    final colorScheme = Theme.of(context).colorScheme;
    // Column labels on the label scale: at titleSmall (15) the two rank
    // labels were cut to "I tr…" / "They t…" on a phone.
    final headerLabelStyle = TenturaText.labelMedium(
      colorScheme.onSurfaceVariant,
    );
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
            const SizedBox(width: kRatingColumnGap),
            Expanded(
              flex: 2,
              child: _RatingSortHeader(
                label: l10n.rankFromYou,
                tooltip: l10n.rankFromYouHint,
                isActive:
                    !isSortedByReverse && !isSortedByAlter && !isSortedByClass,
                isAscending: isSortedByAsc,
                labelStyle: headerLabelStyle,
                alignment: Alignment.center,
                onTap: cubit.sortByDirectColumn,
              ),
            ),
            const SizedBox(width: kRatingColumnGap),
            Expanded(
              flex: 2,
              child: _RatingSortHeader(
                label: l10n.rankToYou,
                tooltip: l10n.rankToYouHint,
                isActive:
                    isSortedByReverse && !isSortedByAlter && !isSortedByClass,
                isAscending: isSortedByAsc,
                labelStyle: headerLabelStyle,
                alignment: Alignment.center,
                onTap: cubit.sortByReverseColumn,
              ),
            ),
            const SizedBox(width: kRatingColumnGap),
            Expanded(
              flex: 2,
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
    this.tooltip,
  });

  final String label;

  /// Explains what the column's number is; defaults to [label].
  final String? tooltip;
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
      message: tooltip ?? label,
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
                    // Two lines before an ellipsis: a phone column is ~70 dp.
                    maxLines: 2,
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
