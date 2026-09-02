import 'package:flutter/material.dart';

/// Modal bottom sheet route that dismisses via [Navigator.maybePop].
///
/// Stock [showModalBottomSheet] calls [Navigator.pop] from the sheet's
/// `onClosing` (drag / handle), which bypasses [PopScope] and
/// [TenturaSheetDismissGuard]. This route keeps drag enabled while still
/// honoring `canPop: false`.
class TenturaModalBottomSheetRoute<T> extends PopupRoute<T> {
  TenturaModalBottomSheetRoute({
    required this.builder,
    this.capturedThemes,
    this.isScrollControlled = true,
    this.scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
    this.showDragHandle = true,
    this.enableDrag = true,
    this.isDismissible = true,
    this.useSafeArea = true,
    this.barrierLabel,
    this.modalBarrierColor,
    super.settings,
  });

  final WidgetBuilder builder;
  final CapturedThemes? capturedThemes;
  final bool isScrollControlled;
  final double scrollControlDisabledMaxHeightRatio;
  final bool showDragHandle;
  final bool enableDrag;
  final bool isDismissible;
  final bool useSafeArea;
  final Color? modalBarrierColor;

  AnimationController? _animationController;

  @override
  Duration get transitionDuration => _kBottomSheetEnterDuration;

  @override
  Duration get reverseTransitionDuration => _kBottomSheetExitDuration;

  @override
  bool get barrierDismissible => isDismissible;

  @override
  final String? barrierLabel;

  @override
  Color get barrierColor => modalBarrierColor ?? Colors.black54;

  @override
  AnimationController createAnimationController() {
    assert(_animationController == null);
    _animationController = BottomSheet.createAnimationController(navigator!);
    return _animationController!;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final sheet = BottomSheet(
      animationController: _animationController,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      onClosing: () {
        if (isCurrent) {
          navigator?.maybePop();
        }
      },
      builder: builder,
    );

    Widget content = useSafeArea
        ? SafeArea(bottom: false, child: sheet)
        : MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: sheet,
          );

    content = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: MaterialLocalizations.of(context).dialogLabel,
      child: content,
    );

    content = AnimatedBuilder(
      animation: animation,
      builder: (context, child) => CustomSingleChildLayout(
        delegate: _TenturaSheetLayout(
          progress: animation.value,
          isScrollControlled: isScrollControlled,
          scrollControlDisabledMaxHeightRatio:
              scrollControlDisabledMaxHeightRatio,
        ),
        child: child,
      ),
      child: content,
    );

    return capturedThemes?.wrap(content) ?? content;
  }
}

const _kBottomSheetEnterDuration = Duration(milliseconds: 250);
const _kBottomSheetExitDuration = Duration(milliseconds: 200);

class _TenturaSheetLayout extends SingleChildLayoutDelegate {
  _TenturaSheetLayout({
    required this.progress,
    required this.isScrollControlled,
    required this.scrollControlDisabledMaxHeightRatio,
  });

  final double progress;
  final bool isScrollControlled;
  final double scrollControlDisabledMaxHeightRatio;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      minWidth: constraints.maxWidth,
      maxWidth: constraints.maxWidth,
      maxHeight: isScrollControlled
          ? constraints.maxHeight
          : constraints.maxHeight * scrollControlDisabledMaxHeightRatio,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(0, size.height - childSize.height * progress);

  @override
  bool shouldRelayout(_TenturaSheetLayout oldDelegate) =>
      progress != oldDelegate.progress ||
      isScrollControlled != oldDelegate.isScrollControlled ||
      scrollControlDisabledMaxHeightRatio !=
          oldDelegate.scrollControlDisabledMaxHeightRatio;
}
