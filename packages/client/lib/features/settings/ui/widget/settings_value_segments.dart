import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// One choice in [SettingsValueSegments].
class SettingsValueSegment<T extends Object> {
  const SettingsValueSegment({
    required this.value,
    required this.label,
    this.icon,
    this.tooltip,
  });

  final T value;
  final String label;
  final Widget? icon;
  final String? tooltip;
}

/// Language / theme pickers: a horizontal [SegmentedButton] on regular width,
/// full-width stacked choices on compact phones so RU labels wrap at word
/// boundaries instead of mid-word inside a cramped segment.
class SettingsValueSegments<T extends Object> extends StatelessWidget {
  const SettingsValueSegments({
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    super.key,
  });

  final List<SettingsValueSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    if (context.windowClass != WindowClass.compact) {
      return SegmentedButton<T>(
        selected: selected,
        showSelectedIcon: false,
        segments: [
          for (final segment in segments)
            ButtonSegment<T>(
              value: segment.value,
              label: Text(segment.label),
              icon: segment.icon,
              tooltip: segment.tooltip ?? segment.label,
            ),
        ],
        onSelectionChanged: onSelectionChanged,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: tt.tightGap,
      children: [
        for (final segment in segments)
          _CompactSegmentTile<T>(
            selected: selected.contains(segment.value),
            label: segment.label,
            icon: segment.icon,
            tooltip: segment.tooltip ?? segment.label,
            onPressed: () => onSelectionChanged({segment.value}),
            scheme: scheme,
            tt: tt,
          ),
      ],
    );
  }
}

class _CompactSegmentTile<T extends Object> extends StatelessWidget {
  const _CompactSegmentTile({
    required this.selected,
    required this.label,
    required this.onPressed,
    required this.scheme,
    required this.tt,
    this.icon,
    this.tooltip,
  });

  final bool selected;
  final String label;
  final Widget? icon;
  final String? tooltip;
  final VoidCallback onPressed;
  final ColorScheme scheme;
  final TenturaTokens tt;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(tt.buttonRadius);
    final background = selected
        ? scheme.secondaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: tooltip ?? label,
      child: Material(
        color: background,
        borderRadius: radius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tt.screenHPadding,
              vertical: tt.listRowPadding.vertical / 2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  IconTheme(
                    data: IconThemeData(color: foreground, size: tt.iconSize),
                    child: icon!,
                  ),
                  SizedBox(width: tt.iconTextGap),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TenturaText.labelLarge(foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
