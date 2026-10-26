import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/semantics_free_tooltip.dart';

import '../bloc/constellation_composer_cubit.dart';
import '../bloc/constellation_cubit.dart';
import 'constellation_create_entry.dart';
import 'constellation_filter_bar.dart';
import 'constellation_person_search.dart';
import 'constellation_selection_layers.dart';

/// Largest system text scale at which the phone title may still be scaled
/// down to fit (#659); above it the title keeps the reader's size.
const double _kTitleShrinkMaxTextScale = 1.05;

/// App-bar row for the constellation field: title, optional legend, filters,
/// and map/text mode switch.
class ConstellationAppBarRow extends StatelessWidget {
  const ConstellationAppBarRow({
    required this.legendExpanded,
    required this.onToggleLegend,
    this.peopleTagsEnabled = kPeopleTagsEnabled,
    super.key,
  });

  final bool legendExpanded;
  final VoidCallback onToggleLegend;
  final bool peopleTagsEnabled;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);

    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.isComposing != current.isComposing ||
          previous.placementPhase != current.placementPhase ||
          previous.viewMode != current.viewMode ||
          previous.filterCapabilitySlugs != current.filterCapabilitySlugs ||
          previous.filterLocation != current.filterLocation ||
          previous.filterTiming != current.filterTiming ||
          previous.filterIncludeUnspecified !=
              current.filterIncludeUnspecified ||
          previous.membershipFilters != current.membershipFilters,
      builder: (context, state) {
        final cubit = context.read<ConstellationCubit>();
        final showLegend = state.viewMode == ConstellationViewMode.map;
        final composer = maybeConstellationComposer(context);
        if (state.isComposing) {
          return Row(
            children: [
              Expanded(
                child: Text(
                  composer?.kind == BeaconKind.post
                      ? l10n.postsTabNewPost
                      : l10n.postCreateMenuRequest,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const Key('constellation.app_bar.cancel_composer'),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close),
                onPressed: composer == null
                    ? null
                    : () => unawaited(() async {
                        await composer.cancel();
                        await composer.finish();
                      }()),
              ),
            ],
          );
        }

        // On a phone (#659) the bar keeps the title, the person search and a
        // full-size Map/List toggle; everything else goes into a menu.
        if (context.windowClass == WindowClass.compact) {
          return Row(
            children: [
              // Never cut to "F…": a title that does not fit is scaled down
              // whole instead — but only at the default text size. Under a
              // larger system text size shrinking it would undo the reader's
              // choice, so it keeps that size and ellipsizes.
              Expanded(
                child:
                    MediaQuery.textScalerOf(context).scale(1) >
                        _kTitleShrinkMaxTextScale
                    ? Text(
                        l10n.constellationTitle,
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          l10n.constellationTitle,
                          style: theme.textTheme.titleLarge,
                          maxLines: 1,
                        ),
                      ),
              ),
              Visibility(
                visible: showLegend,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: const ConstellationPersonSearchButton(),
              ),
              // Not Flexible: the toggle keeps its own (icon-only) size.
              _ConstellationViewModeToggle(
                viewMode: state.viewMode,
                onChanged: cubit.setViewMode,
              ),
              _ConstellationOverflowMenu(
                showMapActions: showLegend,
                legendExpanded: legendExpanded,
                onToggleLegend: onToggleLegend,
              ),
            ],
          );
        }

        final legendLabel = legendExpanded
            ? l10n.graphLegendClose
            : l10n.graphLegendOpen;
        return Row(
          children: [
            Expanded(
              child: Text(
                l10n.constellationTitle,
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Keep a fixed slot so the view-mode toggle does not shift when
            // map→text hides the legend control (RenderFlex / Flexible reflow).
            Visibility(
              visible: showLegend,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              // The icon names the button; the hover tooltip adds no
              // second name (#678).
              child: SemanticsFreeTooltip(
                message: legendLabel,
                child: IconButton(
                  key: const Key('constellation.app_bar.legend'),
                  onPressed: onToggleLegend,
                  icon: Icon(Icons.legend_toggle, semanticLabel: legendLabel),
                  constraints: BoxConstraints(
                    minWidth: tt.buttonHeight,
                    minHeight: tt.buttonHeight,
                  ),
                ),
              ),
            ),
            // The list has its own search field; the map's sits in the same
            // fixed-slot pattern as the legend.
            Visibility(
              visible: showLegend,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: const ConstellationPersonSearchButton(),
            ),
            // Multi-select (#642) works on the map only.
            Visibility(
              visible: showLegend,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: const ConstellationSelectionToggle(),
            ),
            if (composer != null)
              PopupMenuButton<BeaconKind>(
                key: const Key('constellation.app_bar.create_here'),
                tooltip: l10n.constellationCreateHere,
                icon: const Icon(Icons.add),
                popUpAnimationStyle: AnimationStyle.noAnimation,
                itemBuilder: (_) => constellationCreateMenuItems(l10n),
                onSelected: (kind) {
                  final controller = cubit.graphController;
                  final size = controller.viewportSize;
                  if (size == null) {
                    return;
                  }
                  composer.start(
                    kind,
                    controller.viewportLocalToScene(size.center(Offset.zero)),
                  );
                },
              ),
            SemanticsFreeTooltip(
              message: l10n.constellationFiltersOpen,
              child: IconButton(
                key: const Key('constellation.app_bar.filters'),
                onPressed: () => showConstellationFilterSheet(
                  context,
                  cubit: cubit,
                ),
                icon: Badge(
                  isLabelVisible: cubit.hasActiveFilters,
                  smallSize: tt.tightGap,
                  child: Icon(
                    Icons.tune,
                    semanticLabel: l10n.constellationFiltersOpen,
                  ),
                ),
                constraints: BoxConstraints(
                  minWidth: tt.buttonHeight,
                  minHeight: tt.buttonHeight,
                ),
              ),
            ),
            if (peopleTagsEnabled)
              PopupMenuButton<void>(
                key: const Key('constellation.app_bar.menu'),
                popUpAnimationStyle: AnimationStyle.noAnimation,
                itemBuilder: (_) => [
                  PopupMenuItem<void>(
                    key: const Key('constellation.app_bar.people_tags'),
                    onTap: () =>
                        unawaited(context.router.push(const PeopleTagsRoute())),
                    child: Text(l10n.peopleTagsScreenTitle),
                  ),
                ],
              ),
            Flexible(
              child: _ConstellationViewModeToggle(
                viewMode: state.viewMode,
                onChanged: cubit.setViewMode,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ConstellationViewModeToggle extends StatelessWidget {
  const _ConstellationViewModeToggle({
    required this.viewMode,
    required this.onChanged,
  });

  final ConstellationViewMode viewMode;
  final ValueChanged<ConstellationViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final mapLabel = l10n.constellationViewModeMap;
    final textLabel = l10n.constellationViewModeList;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showLabels = _labelsFit(
          context,
          constraints.maxWidth,
          mapLabel: mapLabel,
          textLabel: textLabel,
        );
        // Each segment is named once, by its own label (#678). The tooltip
        // is for the pointer only and sits on the icon: a segment tooltip
        // would add a text node beside the button on hover, and the web
        // reads that as a second name ("Map Map").
        return SegmentedButton<ConstellationViewMode>(
          key: const Key('constellation.app_bar.view_mode'),
          showSelectedIcon: false,
          // Full 48 dp touch targets on every platform (#659).
          style: ButtonStyle(
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
            textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
          ),
          segments: [
            ButtonSegment(
              value: ConstellationViewMode.map,
              icon: SemanticsFreeTooltip(
                message: mapLabel,
                child: Semantics(
                  identifier: TestIds.constellationAppBarViewModeMap,
                  label: mapLabel,
                  child: const Icon(TenturaIcons.graph),
                ),
              ),
              label: showLabels
                  ? ExcludeSemantics(child: Text(mapLabel))
                  : null,
            ),
            ButtonSegment(
              value: ConstellationViewMode.text,
              icon: SemanticsFreeTooltip(
                message: textLabel,
                child: Semantics(
                  identifier: TestIds.constellationAppBarViewModeText,
                  label: textLabel,
                  child: const Icon(Icons.view_list_outlined),
                ),
              ),
              label: showLabels
                  ? ExcludeSemantics(child: Text(textLabel))
                  : null,
            ),
          ],
          selected: {viewMode},
          onSelectionChanged: (selection) {
            onChanged(selection.first);
          },
        );
      },
    );
  }

  static bool _labelsFit(
    BuildContext context,
    double maxWidth, {
    required String mapLabel,
    required String textLabel,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return false;
    }
    final style = Theme.of(context).textTheme.labelMedium ?? const TextStyle();
    final iconSize = IconTheme.of(context).size ?? 24;
    final gap = context.tt.iconTextGap;
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    // Two segments + divider + outer padding allowance.
    const chrome = 48.0;
    final mapW =
        _measure(mapLabel, style, textScaler, textDirection) + iconSize + gap;
    final textW =
        _measure(textLabel, style, textScaler, textDirection) + iconSize + gap;
    return mapW + textW + chrome <= maxWidth;
  }

  static double _measure(
    String text,
    TextStyle style,
    TextScaler textScaler,
    TextDirection textDirection,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}

enum _ConstellationOverflowAction { legend, select, createHere, filters }

/// The phone bar's overflow menu (#659): legend, select several, create here
/// and filters. Its icon carries the active-filters badge.
class _ConstellationOverflowMenu extends StatelessWidget {
  const _ConstellationOverflowMenu({
    required this.showMapActions,
    required this.legendExpanded,
    required this.onToggleLegend,
  });

  final bool showMapActions;
  final bool legendExpanded;
  final VoidCallback onToggleLegend;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<ConstellationCubit>();
    final composer = maybeConstellationComposer(context);
    final selection = showMapActions
        ? maybeConstellationSelection(context)
        : null;

    PopupMenuItem<_ConstellationOverflowAction> item(
      BuildContext menuContext, {
      required _ConstellationOverflowAction action,
      required IconData icon,
      required String label,
      bool badge = false,
      bool? checked,
    }) {
      final color = Theme.of(menuContext).colorScheme.onSurface;
      return PopupMenuItem(
        key: Key('constellation.app_bar.more.${action.name}'),
        value: action,
        child: Semantics(
          toggled: checked,
          child: Row(
            children: [
              Badge(
                isLabelVisible: badge,
                smallSize: tt.tightGap,
                child: Icon(icon, size: tt.iconSize, color: color),
              ),
              SizedBox(width: tt.rowGap),
              Flexible(child: Text(label)),
              if (checked ?? false) ...[
                SizedBox(width: tt.rowGap),
                Icon(Icons.check, size: tt.iconSize, color: color),
              ],
            ],
          ),
        ),
      );
    }

    return PopupMenuButton<_ConstellationOverflowAction>(
      key: const Key('constellation.app_bar.more'),
      icon: Badge(
        isLabelVisible: cubit.hasActiveFilters,
        smallSize: tt.tightGap,
        child: const Icon(Icons.more_vert),
      ),
      constraints: BoxConstraints(
        minWidth: tt.buttonHeight,
        minHeight: tt.buttonHeight,
      ),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      itemBuilder: (menuContext) => [
        if (showMapActions)
          item(
            menuContext,
            action: _ConstellationOverflowAction.legend,
            icon: Icons.legend_toggle,
            label: legendExpanded
                ? l10n.graphLegendClose
                : l10n.graphLegendOpen,
          ),
        if (selection != null)
          item(
            menuContext,
            action: _ConstellationOverflowAction.select,
            icon: Icons.select_all,
            label: l10n.constellationSelectMany,
            checked: selection.state.selecting,
          ),
        if (composer != null)
          item(
            menuContext,
            action: _ConstellationOverflowAction.createHere,
            icon: Icons.add,
            label: l10n.constellationCreateHere,
          ),
        item(
          menuContext,
          action: _ConstellationOverflowAction.filters,
          icon: Icons.tune,
          label: l10n.constellationFiltersOpen,
          badge: cubit.hasActiveFilters,
        ),
      ],
      onSelected: (action) {
        switch (action) {
          case _ConstellationOverflowAction.legend:
            onToggleLegend();
          case _ConstellationOverflowAction.select:
            selection?.setSelecting(!selection.state.selecting);
          case _ConstellationOverflowAction.createHere:
            unawaited(_offerCreate(context, cubit: cubit, composer: composer));
          case _ConstellationOverflowAction.filters:
            unawaited(showConstellationFilterSheet(context, cubit: cubit));
        }
      },
    );
  }

  /// The kind menu, anchored at this button; the composer starts at the
  /// centre of the map, as the wide bar's create button does.
  static Future<void> _offerCreate(
    BuildContext context, {
    required ConstellationCubit cubit,
    required ConstellationComposerCubit? composer,
  }) async {
    final box = context.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (composer == null || box is! RenderBox || overlay is! RenderBox) {
      return;
    }
    final anchor = box.localToGlobal(
      box.size.bottomCenter(Offset.zero),
      ancestor: overlay,
    );
    final kind = await showMenu<BeaconKind>(
      context: context,
      position: RelativeRect.fromRect(
        anchor & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: constellationCreateMenuItems(L10n.of(context)!),
      popUpAnimationStyle: AnimationStyle.noAnimation,
    );
    final controller = cubit.graphController;
    final size = controller.viewportSize;
    if (kind == null || size == null) {
      return;
    }
    composer.start(
      kind,
      controller.viewportLocalToScene(size.center(Offset.zero)),
    );
  }
}
