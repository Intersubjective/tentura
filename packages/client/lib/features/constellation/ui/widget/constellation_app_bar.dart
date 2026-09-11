import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../bloc/constellation_cubit.dart';
import 'constellation_filter_bar.dart';

/// App-bar row for the constellation field: title, optional legend, filters,
/// and map/text mode switch.
class ConstellationAppBarRow extends StatelessWidget {
  const ConstellationAppBarRow({
    required this.legendExpanded,
    required this.onToggleLegend,
    super.key,
  });

  final bool legendExpanded;
  final VoidCallback onToggleLegend;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);

    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
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
              child: IconButton(
                key: const Key('constellation.app_bar.legend'),
                tooltip: legendExpanded
                    ? l10n.graphLegendClose
                    : l10n.graphLegendOpen,
                onPressed: onToggleLegend,
                icon: Icon(
                  legendExpanded ? Icons.map : Icons.map_outlined,
                ),
                constraints: BoxConstraints(
                  minWidth: tt.buttonHeight,
                  minHeight: tt.buttonHeight,
                ),
              ),
            ),
            IconButton(
              key: const Key('constellation.app_bar.filters'),
              tooltip: l10n.constellationFiltersOpen,
              onPressed: () => showConstellationFilterSheet(
                context,
                cubit: cubit,
              ),
              icon: Badge(
                isLabelVisible: cubit.hasActiveFilters,
                smallSize: tt.tightGap,
                child: const Icon(Icons.tune),
              ),
              constraints: BoxConstraints(
                minWidth: tt.buttonHeight,
                minHeight: tt.buttonHeight,
              ),
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
    final textLabel = l10n.constellationViewModeText;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showLabels = _labelsFit(
          context,
          constraints.maxWidth,
          mapLabel: mapLabel,
          textLabel: textLabel,
        );
        return SegmentedButton<ConstellationViewMode>(
          key: const Key('constellation.app_bar.view_mode'),
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
          ),
          segments: [
            ButtonSegment(
              value: ConstellationViewMode.map,
              icon: Semantics(
                identifier: TestIds.constellationAppBarViewModeMap,
                child: const Icon(TenturaIcons.graph),
              ),
              label: showLabels ? Text(mapLabel) : null,
              tooltip: mapLabel,
            ),
            ButtonSegment(
              value: ConstellationViewMode.text,
              icon: Semantics(
                identifier: TestIds.constellationAppBarViewModeText,
                child: const Icon(Icons.view_list_outlined),
              ),
              label: showLabels ? Text(textLabel) : null,
              tooltip: textLabel,
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
    final style =
        Theme.of(context).textTheme.labelMedium ?? const TextStyle();
    final iconSize = IconTheme.of(context).size ?? 24;
    final gap = context.tt.iconTextGap;
    // Two segments + divider + outer padding allowance.
    const chrome = 48.0;
    final mapW = _measure(mapLabel, style) + iconSize + gap;
    final textW = _measure(textLabel, style) + iconSize + gap;
    return mapW + textW + chrome <= maxWidth;
  }

  static double _measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}
