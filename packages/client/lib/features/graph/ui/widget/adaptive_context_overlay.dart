import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Positions a context card on a graph canvas: bottom dock on compact,
/// fixed-width right rail on regular/expanded ([WindowClass]).
class AdaptiveContextOverlay extends StatelessWidget {
  const AdaptiveContextOverlay({
    required this.child,
    this.compactDetents = false,
    this.mapStackHeight,
    this.onDismiss,
    this.onCompactExtentChanged,
    this.onCompactDetentExpandedChanged,
    super.key,
  });

  final Widget child;

  /// When true on compact widths, the child is a peek/expanded bottom sheet
  /// sized against [mapStackHeight] instead of a fixed screen fraction.
  final bool compactDetents;

  /// Height of the map stack hosting this overlay (compact detents only).
  final double? mapStackHeight;

  final VoidCallback? onDismiss;

  /// Live sheet height in logical px (compact detents only).
  final ValueChanged<double>? onCompactExtentChanged;

  /// `true` while the sheet is on its expanded detent (compact detents only).
  final ValueChanged<bool>? onCompactDetentExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;

    if (context.windowClass == WindowClass.compact) {
      if (compactDetents && mapStackHeight != null) {
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _CompactDetentSheet(
            mapStackHeight: mapStackHeight!,
            onDismiss: onDismiss,
            onExtentChanged: onCompactExtentChanged,
            onDetentExpandedChanged: onCompactDetentExpandedChanged,
            child: child,
          ),
        );
      }
      return Positioned(
        left: tt.screenHPadding,
        right: tt.screenHPadding,
        bottom: 0,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: tt.rowGap),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.sizeOf(context).height *
                    tt.graphPersonContextCompactMaxHeightFraction,
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    return Positioned(
      top: tt.rowGap,
      right: tt.screenHPadding,
      bottom: tt.rowGap,
      width: tt.graphPersonContextWidth,
      child: SafeArea(
        left: false,
        child: child,
      ),
    );
  }
}

enum _SheetDetent { peek, expanded }

class _CompactDetentSheet extends StatefulWidget {
  const _CompactDetentSheet({
    required this.mapStackHeight,
    required this.child,
    this.onDismiss,
    this.onExtentChanged,
    this.onDetentExpandedChanged,
  });

  final double mapStackHeight;
  final Widget child;
  final VoidCallback? onDismiss;
  final ValueChanged<double>? onExtentChanged;
  final ValueChanged<bool>? onDetentExpandedChanged;

  @override
  State<_CompactDetentSheet> createState() => _CompactDetentSheetState();
}

class _CompactDetentSheetState extends State<_CompactDetentSheet>
    with SingleTickerProviderStateMixin {
  static const _snapDuration = Duration(milliseconds: 250);
  static const _dismissFlingVelocity = 700.0;
  static const _dismissDragFraction = 0.25;

  _SheetDetent _detent = _SheetDetent.peek;
  double _dragOffset = 0;
  late final AnimationController _snap;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(vsync: this, duration: _snapDuration);
    _snap.addListener(_reportExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportExtent();
      _reportDetentExpanded();
    });
  }

  @override
  void dispose() {
    _snap.removeListener(_reportExtent);
    _snap.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CompactDetentSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mapStackHeight != widget.mapStackHeight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _reportExtent();
      });
    }
  }

  TenturaTokens get _tt => context.tt;

  double get _peekCap => widget.mapStackHeight * _tt.fieldSheetPeekFraction;

  double get _expandedCap =>
      math.max(0, widget.mapStackHeight - _tt.fieldSheetMinMapHeight);

  double _capFor(_SheetDetent detent) =>
      detent == _SheetDetent.peek ? _peekCap : _expandedCap;

  double get _targetHeight => _capFor(_detent);

  double get _displayHeight =>
      (_targetHeight - _dragOffset).clamp(0.0, widget.mapStackHeight);

  void _reportExtent() {
    widget.onExtentChanged?.call(_displayHeight);
  }

  void _reportDetentExpanded() {
    widget.onDetentExpandedChanged?.call(_detent == _SheetDetent.expanded);
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _toggleDetent() {
    final next = _detent == _SheetDetent.peek
        ? _SheetDetent.expanded
        : _SheetDetent.peek;
    _setDetent(next, announce: true);
  }

  void _setDetent(_SheetDetent detent, {required bool announce}) {
    setState(() {
      _detent = detent;
      _dragOffset = 0;
    });
    _reportDetentExpanded();
    if (_reduceMotion) {
      _snap.value = 1;
      _reportExtent();
    } else {
      _snap.forward(from: 0);
    }
    if (announce) {
      final l10n = L10n.of(context)!;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          detent == _SheetDetent.expanded
              ? l10n.fieldContextSheetExpandedAnnouncement
              : l10n.fieldContextSheetCollapsedAnnouncement,
          Directionality.of(context),
        ),
      );
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      _dragOffset = _dragOffset.clamp(
        -(_expandedCap - _peekCap),
        _targetHeight + _peekCap * _dismissDragFraction,
      );
    });
    _reportExtent();
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_detent == _SheetDetent.peek &&
        (velocity > _dismissFlingVelocity ||
            _dragOffset > _peekCap * _dismissDragFraction)) {
      widget.onDismiss?.call();
      setState(() => _dragOffset = 0);
      _reportExtent();
      return;
    }
    if (velocity.abs() >= _dismissFlingVelocity) {
      if (velocity < 0) {
        _setDetent(_SheetDetent.expanded, announce: true);
      } else if (_detent == _SheetDetent.expanded) {
        _setDetent(_SheetDetent.peek, announce: true);
      } else {
        widget.onDismiss?.call();
      }
      return;
    }
    final mid = (_peekCap + _expandedCap) / 2;
    if (_displayHeight >= mid) {
      _setDetent(
        _SheetDetent.expanded,
        announce: _detent != _SheetDetent.expanded,
      );
    } else if (_dragOffset > _peekCap * _dismissDragFraction &&
        _detent == _SheetDetent.peek) {
      widget.onDismiss?.call();
    } else {
      _setDetent(_SheetDetent.peek, announce: _detent != _SheetDetent.peek);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    final expanded = _detent == _SheetDetent.expanded;
    final sheetColor =
        theme.bottomSheetTheme.backgroundColor ?? theme.colorScheme.surface;

    return AnimatedContainer(
      duration: _dragOffset != 0 || _reduceMotion
          ? Duration.zero
          : _snapDuration,
      curve: Curves.easeOutCubic,
      height: _displayHeight,
      child: Material(
        color: sheetColor,
        elevation: theme.bottomSheetTheme.elevation ?? 4,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tt.cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              key: const Key('field.context_sheet.handle'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              onTap: _toggleDetent,
              child: Actions(
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      _toggleDetent();
                      return null;
                    },
                  ),
                },
                child: Focus(
                  child: Semantics(
                    button: true,
                    label: expanded
                        ? l10n.fieldContextSheetCollapse
                        : l10n.fieldContextSheetExpand,
                    child: SizedBox(
                      width: double.infinity,
                      height: tt.fieldSheetDragHandleHitSize,
                      child: Center(
                        child: Container(
                          width: tt.fieldSheetDragHandleWidth,
                          height: tt.fieldSheetDragHandleHeight,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(
                              tt.fieldSheetDragHandleHeight / 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}
