import 'dart:async';

import 'package:flutter/material.dart';

import 'tentura_count_badge.dart';
import '../tentura_text.dart';
import '../tentura_tokens.dart';

enum TenturaTabCountStyle { badge, plainText }

/// How the equal-width tabs of a row with icons are drawn (#609).
enum _TabLabelMode { iconAndLabel, labelOnly, iconOnly }

/// Icon size for tabs with [TenturaUnderlineTabs.icons] — matches HUD row icons
/// so the 48px pinned beacon bar stays valid across WindowClass.
const double _kTabIconSize = 20;

/// Underline tab row: full-width bottom border; active tab 2px sky underline.
///
/// Optional [attentionIndex] + [attentionActive] pulse a soft highlight on that
/// tab (respects [MediaQuery.disableAnimationsOf] with a static highlight).
///
/// When [icons] is set and icon+text does not fit each equal slot, the row
/// first drops the icons and keeps the labels (#609); only when a label alone
/// does not fit either does it show icons only. Every flex tab takes the same
/// step, and badges are not part of that fit decision.
class TenturaUnderlineTabs extends StatefulWidget {
  const TenturaUnderlineTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    this.icons,
    this.badges,
    this.badgeBackgroundColors,
    this.secondaryBadges,
    this.dots,
    this.dotSemanticsLabel,
    this.tabIds,
    this.attentionIndex,
    this.attentionActive = false,
    this.countStyle = TenturaTabCountStyle.badge,
    this.compactIconTabs = const {},
    super.key,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// Optional per-tab icons. Same length as [tabs] when non-null.
  final List<IconData>? icons;

  final List<int?>? badges;

  /// Optional per-tab primary badge fill. Same length as [tabs] when non-null;
  /// null entry uses [TenturaTokens.info].
  final List<Color?>? badgeBackgroundColors;

  /// Optional per-tab second count (e.g. warn-styled chip). Same length as
  /// [tabs] when non-null; entries null or <=0 are hidden.
  final List<int?>? secondaryBadges;

  /// Optional per-tab attention dot (something to look at, no count). Same
  /// length as [tabs] when non-null; hidden while the tab shows a badge.
  final List<bool>? dots;

  /// Screen-reader text of a dot (e.g. «Plan: a step needs you»).
  final String? dotSemanticsLabel;

  /// Optional stable ids for test keys. Same length as [tabs] when non-null.
  final List<String>? tabIds;

  /// Tab index to emphasize when [attentionActive] is true.
  final int? attentionIndex;

  /// When true (with a valid [attentionIndex]), show pulse or static highlight.
  final bool attentionActive;

  /// How [badges] / [secondaryBadges] render. Default [badge] keeps Beacon chips.
  final TenturaTabCountStyle countStyle;

  /// Indices rendered at a fixed compact width, icon-only, outside the
  /// equal-width distribution — for a secondary tab at the row's end.
  final Set<int> compactIconTabs;

  @override
  State<TenturaUnderlineTabs> createState() => _TenturaUnderlineTabsState();
}

class _TenturaUnderlineTabsState extends State<TenturaUnderlineTabs>
    with SingleTickerProviderStateMixin {
  AnimationController? _attentionController;

  static const double _staticAttentionOpacity = 0.12;
  static const double _animatedAttentionOpacityMin = 0.06;
  static const double _animatedAttentionOpacityRange = 0.14;

  bool get _attentionTargetValid {
    final i = widget.attentionIndex;
    return i != null && i >= 0 && i < widget.tabs.length;
  }

  bool get _shouldShowAttention =>
      widget.attentionActive && _attentionTargetValid;

  void _syncAttentionAnimation() {
    if (!_shouldShowAttention) {
      _attentionController?.dispose();
      _attentionController = null;
      return;
    }

    final disableMotion = MediaQuery.disableAnimationsOf(context);
    if (disableMotion) {
      _attentionController?.dispose();
      _attentionController = null;
      return;
    }

    _attentionController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    if (!_attentionController!.isAnimating) {
      unawaited(_attentionController!.repeat(reverse: true));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAttentionAnimation();
  }

  @override
  void didUpdateWidget(TenturaUnderlineTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attentionActive != widget.attentionActive ||
        oldWidget.attentionIndex != widget.attentionIndex ||
        oldWidget.tabs.length != widget.tabs.length) {
      _syncAttentionAnimation();
    }
  }

  @override
  void dispose() {
    _attentionController?.dispose();
    super.dispose();
  }

  /// Whether icon+label fits every equal slot, else whether the label alone
  /// does (#609: «Обсуждение» with its icon is wider than a quarter of a
  /// phone, so the row keeps its words and drops the icons first). Badges
  /// are ignored so count chips do not flip the whole row between modes.
  /// [compactIconTabs] are excluded — they are always icon-only.
  _TabLabelMode _labelMode(BuildContext context, double maxWidth) {
    final icons = widget.icons;
    if (icons == null || icons.isEmpty || widget.tabs.isEmpty) {
      return _TabLabelMode.iconAndLabel;
    }
    final n = widget.tabs.length;
    final compact = widget.compactIconTabs;
    final compactCount = compact.where((i) => i >= 0 && i < n).length;
    final flexCount = n - compactCount;
    if (flexCount == 0) {
      return _TabLabelMode.iconAndLabel;
    }
    final tt = context.tt;
    final fixedTotal = compactCount * tt.tabCompactWidth;
    final slotWidth = (maxWidth - fixedTotal) / flexCount;
    final textScaler = MediaQuery.textScalerOf(context);
    final style = TenturaText.tabLabel(tt.text);

    var widestLabel = 0.0;
    for (var i = 0; i < n; i++) {
      if (compact.contains(i)) {
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(text: widget.tabs[i], style: style),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widestLabel) widestLabel = painter.width;
      painter.dispose();
    }
    if (_kTabIconSize + tt.iconTextGap + widestLabel <= slotWidth) {
      return _TabLabelMode.iconAndLabel;
    }
    return widestLabel <= slotWidth
        ? _TabLabelMode.labelOnly
        : _TabLabelMode.iconOnly;
  }

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  double _countWidth(BuildContext context, int count) {
    final tt = context.tt;
    if (widget.countStyle == TenturaTabCountStyle.plainText) {
      return _textWidth(
        context,
        '$count',
        TenturaText.withTabular(TenturaText.bodySmall(tt.text)),
      );
    }
    // TenturaCountBadge: 5 px padding each side, at least 18 px wide.
    final text = _textWidth(
      context,
      count > 99 ? '99+' : '$count',
      TenturaText.labelSmall(tt.text),
    );
    return text + 10 < 18 ? 18 : text + 10;
  }

  /// What a flex tab's content needs: icon, label, inline counts or dot.
  double _contentWidth(BuildContext context, int i, _TabLabelMode mode) {
    final tt = context.tt;
    final showIcon =
        mode != _TabLabelMode.labelOnly &&
        widget.icons != null &&
        i < widget.icons!.length;
    final showLabel = mode != _TabLabelMode.iconOnly;
    var width = 0.0;
    if (showIcon) width += _kTabIconSize + (showLabel ? tt.iconTextGap : 0);
    if (showLabel) {
      width += _textWidth(
        context,
        widget.tabs[i],
        TenturaText.tabLabel(tt.text),
      );
    }
    final badge = widget.badges != null && i < widget.badges!.length
        ? widget.badges![i]
        : null;
    final secondary =
        widget.secondaryBadges != null && i < widget.secondaryBadges!.length
        ? widget.secondaryBadges![i]
        : null;
    final hasPrimary = badge != null && badge > 0;
    final hasSecondary = secondary != null && secondary > 0;
    if (hasPrimary || hasSecondary) {
      width += tt.iconTextGap;
      if (hasPrimary) width += _countWidth(context, badge);
      if (hasPrimary && hasSecondary) width += tt.tightGap;
      if (hasSecondary) width += _countWidth(context, secondary);
    } else if (widget.dots != null &&
        i < widget.dots!.length &&
        widget.dots![i]) {
      width += tt.tightGap + tt.unreadDotSize;
    }
    // Sub-pixel slack, so a label that fits is never ellipsised by rounding.
    return width.ceilToDouble() + 1;
  }

  /// Flex factors for the non-compact tabs (#930). Equal slots while every
  /// tab's content fits one; otherwise the width is shared by content, so a
  /// tab with a count («Обсуждение ❶») keeps its whole label and the
  /// shorter tabs give up what they do not use.
  List<int>? _contentFlexes(
    BuildContext context,
    double maxWidth,
    _TabLabelMode mode,
  ) {
    if (!maxWidth.isFinite) return null;
    final n = widget.tabs.length;
    final compact = widget.compactIconTabs;
    final flexIndices = [
      for (var i = 0; i < n; i++)
        if (!compact.contains(i)) i,
    ];
    if (flexIndices.isEmpty) return null;
    final available =
        maxWidth -
        compact.where((i) => i >= 0 && i < n).length *
            context.tt.tabCompactWidth;
    final slot = available / flexIndices.length;
    final needed = {
      for (final i in flexIndices) i: _contentWidth(context, i, mode),
    };
    if (needed.values.every((w) => w <= slot)) return null;
    final total = needed.values.fold<double>(0, (a, b) => a + b);
    final share = total < available
        ? (available - total) / flexIndices.length
        : 0.0;
    return List.generate(n, (i) {
      final width = needed[i];
      return width == null
          ? 0
          : ((width + share) * 100).round().clamp(1, 1 << 30);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final staticOpacity = _shouldShowAttention && disableMotion
        ? _staticAttentionOpacity
        : 0.0;
    final hasIcons = widget.icons != null && widget.icons!.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: tt.border),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mode = hasIcons
              ? _labelMode(context, constraints.maxWidth)
              : _TabLabelMode.iconAndLabel;
          final flexes = _contentFlexes(context, constraints.maxWidth, mode);
          return Row(
            children: [
              for (var i = 0; i < widget.tabs.length; i++)
                if (widget.compactIconTabs.contains(i))
                  SizedBox(
                    width: tt.tabCompactWidth,
                    child: _buildTabCell(
                      context,
                      index: i,
                      showLabel: false,
                      badgeOverlay: true,
                      staticAttentionOpacity: i == widget.attentionIndex
                          ? staticOpacity
                          : 0.0,
                    ),
                  )
                else
                  Expanded(
                    flex: flexes?[i] ?? 1,
                    child: _buildTabCell(
                      context,
                      index: i,
                      showLabel: mode != _TabLabelMode.iconOnly,
                      showIcon: mode != _TabLabelMode.labelOnly,
                      badgeOverlay: false,
                      staticAttentionOpacity: i == widget.attentionIndex
                          ? staticOpacity
                          : 0.0,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabCell(
    BuildContext context, {
    required int index,
    required bool showLabel,
    required bool badgeOverlay,
    required double staticAttentionOpacity,
    bool showIcon = true,
  }) {
    final badge = widget.badges != null && index < widget.badges!.length
        ? widget.badges![index]
        : null;
    final secondaryBadge =
        widget.secondaryBadges != null && index < widget.secondaryBadges!.length
        ? widget.secondaryBadges![index]
        : null;
    final badgeBackground =
        widget.badgeBackgroundColors != null &&
            index < widget.badgeBackgroundColors!.length
        ? widget.badgeBackgroundColors![index]
        : null;
    final icon =
        showIcon && widget.icons != null && index < widget.icons!.length
        ? widget.icons![index]
        : null;
    final dot =
        widget.dots != null &&
        index < widget.dots!.length &&
        widget.dots![index];

    final useAnimatedAttention =
        _shouldShowAttention &&
        index == widget.attentionIndex &&
        _attentionController != null;

    Widget cell({required double attentionOpacity}) => _TabCell(
      key: widget.tabIds != null && index < widget.tabIds!.length
          ? ValueKey<String>(widget.tabIds![index])
          : null,
      label: widget.tabs[index],
      icon: icon,
      showLabel: showLabel,
      badgeOverlay: badgeOverlay,
      semanticsIdentifier:
          widget.tabIds != null && index < widget.tabIds!.length
          ? widget.tabIds![index]
          : null,
      selected: index == widget.selectedIndex,
      onTap: () => widget.onChanged(index),
      badge: badge,
      badgeBackgroundColor: badgeBackground,
      secondaryBadge: secondaryBadge,
      dot: dot,
      dotSemanticsLabel: widget.dotSemanticsLabel,
      attentionBackgroundOpacity: attentionOpacity,
      countStyle: widget.countStyle,
    );

    if (!useAnimatedAttention) {
      return cell(attentionOpacity: staticAttentionOpacity);
    }

    final controller = _attentionController!;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final opacity =
            _animatedAttentionOpacityMin +
            controller.value * _animatedAttentionOpacityRange;
        return cell(attentionOpacity: opacity);
      },
    );
  }
}

class _TabCell extends StatelessWidget {
  const _TabCell({
    required this.label,
    required this.semanticsIdentifier,
    required this.selected,
    required this.onTap,
    required this.showLabel,
    this.badgeOverlay = false,
    this.icon,
    this.badge,
    this.badgeBackgroundColor,
    this.secondaryBadge,
    this.dot = false,
    this.dotSemanticsLabel,
    this.attentionBackgroundOpacity = 0.0,
    this.countStyle = TenturaTabCountStyle.badge,
    super.key,
  });

  final String label;
  final IconData? icon;
  final bool showLabel;
  final bool badgeOverlay;
  final String? semanticsIdentifier;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;
  final Color? badgeBackgroundColor;
  final int? secondaryBadge;
  final bool dot;
  final String? dotSemanticsLabel;
  final double attentionBackgroundOpacity;
  final TenturaTabCountStyle countStyle;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final active = tt.info;
    final inactive = tt.textMuted;
    final color = selected ? active : inactive;
    final hasPrimaryBadge = badge != null && badge! > 0;
    final hasSecondaryBadge = secondaryBadge != null && secondaryBadge! > 0;
    final hasAnyBadge = hasPrimaryBadge || hasSecondaryBadge;
    final showAttention = attentionBackgroundOpacity > 0;
    final iconOnly = icon != null && !showLabel;

    Widget? iconWidget;
    if (icon != null) {
      iconWidget = Icon(icon, size: _kTabIconSize, color: color);
      if (badgeOverlay && (hasPrimaryBadge || hasSecondaryBadge)) {
        final overlayCount = hasPrimaryBadge ? badge! : secondaryBadge!;
        final overlayColor = hasPrimaryBadge
            ? (badgeBackgroundColor ?? tt.info)
            : tt.warn;
        iconWidget = Stack(
          clipBehavior: Clip.none,
          children: [
            iconWidget,
            Positioned(
              top: -6,
              right: -10,
              child: TenturaCountBadge(
                count: overlayCount,
                backgroundColor: overlayColor,
              ),
            ),
          ],
        );
      }
    }

    final dotWidget = dot && !hasAnyBadge
        ? Padding(
            padding: EdgeInsets.only(left: tt.tightGap),
            child: Semantics(
              label: dotSemanticsLabel,
              child: SizedBox.square(
                key: const ValueKey<String>('tentura-tab-dot'),
                dimension: tt.unreadDotSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tt.info,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          )
        : null;

    // Counts sit right after their label (Material 3 tabs): pinned to the
    // slot's far edge they read as a separate tab ("Unread      2").
    final inlineBadges = !badgeOverlay && hasAnyBadge
        ? Padding(
            padding: EdgeInsets.only(left: tt.iconTextGap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasPrimaryBadge)
                  countStyle == TenturaTabCountStyle.plainText
                      ? Text(
                          '${badge!}',
                          style: TenturaText.withTabular(
                            TenturaText.bodySmall(color),
                          ),
                        )
                      : TenturaCountBadge(
                          count: badge!,
                          backgroundColor: badgeBackgroundColor ?? tt.info,
                        ),
                if (hasPrimaryBadge && hasSecondaryBadge)
                  SizedBox(width: tt.tightGap),
                if (hasSecondaryBadge)
                  countStyle == TenturaTabCountStyle.plainText
                      ? Text(
                          '${secondaryBadge!}',
                          style: TenturaText.withTabular(
                            TenturaText.bodySmall(tt.warn),
                          ),
                        )
                      : TenturaCountBadge(
                          count: secondaryBadge!,
                          backgroundColor: tt.warn,
                        ),
              ],
            ),
          )
        : null;

    Widget content = Padding(
      padding: EdgeInsets.symmetric(vertical: tt.rowGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (iconWidget != null) ...[
                      iconWidget,
                      if (showLabel) SizedBox(width: tt.iconTextGap),
                    ],
                    if (showLabel)
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TenturaText.tabLabel(color),
                        ),
                      ),
                    ?inlineBadges,
                    ?dotWidget,
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Full slot width: with a height alone the indicator laid out at
          // zero width and the active tab was told apart by colour only.
          SizedBox(
            height: 2,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? active : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(1),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (iconOnly) {
      content = Tooltip(message: label, child: content);
    }

    return Semantics(
      identifier: semanticsIdentifier,
      label: iconOnly ? label : null,
      button: true,
      selected: selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: kMinInteractiveDimension,
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (showAttention)
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: tt.rowGap,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(
                          alpha: attentionBackgroundOpacity,
                        ),
                        borderRadius: BorderRadius.circular(tt.buttonRadius),
                      ),
                    ),
                  ),
                ),
              content,
            ],
          ),
        ),
      ),
    );
  }
}
