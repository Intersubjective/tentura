import 'dart:async';

import 'package:flutter/material.dart';

import 'tentura_count_badge.dart';
import '../tentura_text.dart';
import '../tentura_tokens.dart';

enum TenturaTabCountStyle { badge, plainText }

/// Icon size for tabs with [TenturaUnderlineTabs.icons] — matches HUD row icons
/// so the 48px pinned beacon bar stays valid across WindowClass.
const double _kTabIconSize = 20;

/// Underline tab row: full-width bottom border; active tab 2px sky underline.
///
/// Optional [attentionIndex] + [attentionActive] pulse a soft highlight on that
/// tab (respects [MediaQuery.disableAnimationsOf] with a static highlight).
///
/// When [icons] is set, labels hide together if icon+text does not fit each
/// equal slot (badges are not part of that fit decision).
class TenturaUnderlineTabs extends StatefulWidget {
  const TenturaUnderlineTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    this.icons,
    this.badges,
    this.badgeBackgroundColors,
    this.secondaryBadges,
    this.tabIds,
    this.attentionIndex,
    this.attentionActive = false,
    this.countStyle = TenturaTabCountStyle.badge,
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

  /// Optional stable ids for test keys. Same length as [tabs] when non-null.
  final List<String>? tabIds;

  /// Tab index to emphasize when [attentionActive] is true.
  final int? attentionIndex;

  /// When true (with a valid [attentionIndex]), show pulse or static highlight.
  final bool attentionActive;

  /// How [badges] / [secondaryBadges] render. Default [badge] keeps Beacon chips.
  final TenturaTabCountStyle countStyle;

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

  /// Whether icon+label fits every equal slot. Badges are ignored so count
  /// chips do not flip the whole row between labeled and icon-only.
  bool _labelsFit(BuildContext context, double maxWidth) {
    final icons = widget.icons;
    if (icons == null || icons.isEmpty || widget.tabs.isEmpty) {
      return true;
    }
    final n = widget.tabs.length;
    final slotWidth = maxWidth / n;
    final tt = context.tt;
    final textScaler = MediaQuery.textScalerOf(context);
    final style = TenturaText.tabLabel(tt.text);

    for (var i = 0; i < n; i++) {
      final painter = TextPainter(
        text: TextSpan(text: widget.tabs[i], style: style),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final needed = _kTabIconSize + tt.iconTextGap + painter.width;
      painter.dispose();
      if (needed > slotWidth) {
        return false;
      }
    }
    return true;
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
          final showLabels = !hasIcons ||
              _labelsFit(context, constraints.maxWidth);
          return Row(
            children: [
              for (var i = 0; i < widget.tabs.length; i++)
                Expanded(
                  child: _buildTabCell(
                    context,
                    index: i,
                    showLabel: showLabels,
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
    required double staticAttentionOpacity,
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
    final icon = widget.icons != null && index < widget.icons!.length
        ? widget.icons![index]
        : null;

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
      semanticsIdentifier:
          widget.tabIds != null && index < widget.tabIds!.length
          ? widget.tabIds![index]
          : null,
      selected: index == widget.selectedIndex,
      onTap: () => widget.onChanged(index),
      badge: badge,
      badgeBackgroundColor: badgeBackground,
      secondaryBadge: secondaryBadge,
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
    this.icon,
    this.badge,
    this.badgeBackgroundColor,
    this.secondaryBadge,
    this.attentionBackgroundOpacity = 0.0,
    this.countStyle = TenturaTabCountStyle.badge,
    super.key,
  });

  final String label;
  final IconData? icon;
  final bool showLabel;
  final String? semanticsIdentifier;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;
  final Color? badgeBackgroundColor;
  final int? secondaryBadge;
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
                    if (icon != null) ...[
                      Icon(icon, size: _kTabIconSize, color: color),
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
                  ],
                ),
              ),
              if (hasAnyBadge) ...[
                SizedBox(width: tt.iconTextGap),
                Padding(
                  padding: EdgeInsets.only(right: tt.iconTextGap),
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
                                backgroundColor:
                                    badgeBackgroundColor ?? tt.info,
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
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 2,
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
    );
  }
}
