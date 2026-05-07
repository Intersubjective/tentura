import 'dart:async';

import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';

/// Underline tab row: full-width bottom border; active tab 2px sky underline.
///
/// Optional [attentionIndex] + [attentionActive] pulse a soft highlight on that
/// tab (respects [MediaQuery.disableAnimationsOf] with a static highlight).
class TenturaUnderlineTabs extends StatefulWidget {
  const TenturaUnderlineTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    this.badges,
    this.attentionIndex,
    this.attentionActive = false,
    super.key,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<int?>? badges;

  /// Tab index to emphasize when [attentionActive] is true.
  final int? attentionIndex;

  /// When true (with a valid [attentionIndex]), show pulse or static highlight.
  final bool attentionActive;

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

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final staticOpacity = _shouldShowAttention && disableMotion
        ? _staticAttentionOpacity
        : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: tt.border),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < widget.tabs.length; i++)
            Expanded(
              child: _buildTabCell(
                context,
                index: i,
                staticAttentionOpacity: i == widget.attentionIndex
                    ? staticOpacity
                    : 0.0,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabCell(
    BuildContext context, {
    required int index,
    required double staticAttentionOpacity,
  }) {
    final badge = widget.badges != null && index < widget.badges!.length
        ? widget.badges![index]
        : null;

    final useAnimatedAttention =
        _shouldShowAttention &&
        index == widget.attentionIndex &&
        _attentionController != null;

    final cell = _TabCell(
      label: widget.tabs[index],
      selected: index == widget.selectedIndex,
      onTap: () => widget.onChanged(index),
      badge: badge,
      attentionBackgroundOpacity: staticAttentionOpacity,
    );

    if (!useAnimatedAttention) {
      return cell;
    }

    final controller = _attentionController!;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final opacity =
            _animatedAttentionOpacityMin +
            controller.value * _animatedAttentionOpacityRange;
        return _TabCell(
          label: widget.tabs[index],
          selected: index == widget.selectedIndex,
          onTap: () => widget.onChanged(index),
          badge: badge,
          attentionBackgroundOpacity: opacity,
        );
      },
    );
  }
}

class _TabCell extends StatelessWidget {
  const _TabCell({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
    this.attentionBackgroundOpacity = 0.0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;
  final double attentionBackgroundOpacity;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final active = tt.info;
    final inactive = tt.textMuted;
    final hasBadge = badge != null && badge! > 0;
    final showAttention = attentionBackgroundOpacity > 0;

    return InkWell(
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
          Padding(
            padding: EdgeInsets.symmetric(vertical: tt.rowGap),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TenturaText.tabLabel(
                          selected ? active : inactive,
                        ),
                      ),
                    ),
                    if (hasBadge) ...[
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _BadgeBubble(count: badge!),
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
          ),
        ],
      ),
    );
  }
}

class _BadgeBubble extends StatelessWidget {
  const _BadgeBubble({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tt.info,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Center(
            child: Text(
              '$count',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TenturaText.labelSmall(Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
