import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../tentura_tokens.dart';
import '../tentura_window_class.dart';
import 'tentura_modal_bottom_sheet_route.dart';

/// Shows app-owned modal content as a bottom sheet on compact windows and as a
/// centered constrained dialog on regular/expanded windows.
///
/// Compact sheets use [TenturaModalBottomSheetRoute] so drag-to-dismiss goes
/// through [Navigator.maybePop] and respects [TenturaSheetDismissGuard].
///
/// Escape closes the sheet through [Navigator.maybePop] even when keyboard
/// focus is not inside it (on the web the browser can park focus outside the
/// route), unless [isDismissible] is false. On close, keyboard focus returns to
/// the control that opened the sheet; a text field that held focus is not
/// refocused (#403).
///
/// While the sheet animates away the route no longer takes taps, so the
/// second tap of a double tap on its last button would land on the page
/// underneath (#684). For [kTenturaSheetCloseTapShield] after it closes a
/// transparent layer swallows taps on the page. Taps that reach the app before
/// the next frame (a fast double click) are swallowed by the closing sheet
/// itself, so its button cannot pop the page under it.
Future<T?> showTenturaAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = true,
  bool useRootNavigator = false,
  bool useSafeArea = true,
  bool enableDrag = true,
  bool isDismissible = true,
  double? maxWidth,
  double maxHeightFraction = 0.9,
}) async {
  final windowClass = windowClassForWidth(MediaQuery.sizeOf(context).width);
  final trigger = FocusManager.instance.primaryFocus;
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final T? result;
  if (windowClass == WindowClass.compact) {
    final localizations = MaterialLocalizations.of(context);
    result = await navigator.push<T>(
      TenturaModalBottomSheetRoute<T>(
        builder: (sheetContext) => _AbsorbTapsWhileClosing(
          child: _EscapeDismissesSheet(
            child: builder(sheetContext),
          ),
        ),
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
        isScrollControlled: isScrollControlled,
        showDragHandle: showDragHandle,
        enableDrag: enableDrag,
        isDismissible: isDismissible,
        useSafeArea: useSafeArea,
        barrierLabel: localizations.scrimLabel,
        modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      ),
    );
  } else {
    result = await showDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      barrierDismissible: isDismissible,
      builder: (dialogContext) {
        final tt = dialogContext.tt;
        final size = MediaQuery.sizeOf(dialogContext);
        final resolvedMaxWidth = maxWidth ?? tt.contentMaxWidth ?? size.width;
        final maxHeight = size.height * maxHeightFraction;
        final child = builder(dialogContext);

        return _AbsorbTapsWhileClosing(
          child: SafeArea(
            child: Dialog(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: resolvedMaxWidth,
                  maxHeight: maxHeight,
                ),
                child: _EscapeDismissesSheet(child: child),
              ),
            ),
          ),
        );
      },
    );
  }
  _shieldTapsAfterClose(navigator);
  _restoreFocusAfterSheet(trigger);
  return result;
}

/// How long taps on the page are swallowed after a sheet closes: its exit
/// animation plus the gap of a quick double tap or double click (#684).
const kTenturaSheetCloseTapShield = Duration(milliseconds: 400);

/// Puts a transparent, tap-swallowing layer over [navigator]'s overlay for
/// [kTenturaSheetCloseTapShield].
void _shieldTapsAfterClose(NavigatorState navigator) {
  final overlay = navigator.mounted ? navigator.overlay : null;
  if (overlay == null || !overlay.mounted) return;
  late final OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry
      ..remove()
      ..dispose();
  }

  entry = OverlayEntry(builder: (_) => _TapShield(onDone: remove));
  overlay.insert(entry);
}

/// Swallows pointer events for [kTenturaSheetCloseTapShield], then calls
/// [onDone]. Timed by a ticker, not a timer, so it ends with the frames
/// (and never outlives a widget test as a pending timer). Taken out of the
/// tree early (its overlay rebuilt without it), it calls [onDone] too, so
/// the entry never comes back as a fresh shield.
class _TapShield extends StatefulWidget {
  const _TapShield({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_TapShield> createState() => _TapShieldState();
}

class _TapShieldState extends State<_TapShield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: kTenturaSheetCloseTapShield,
  );

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _clock.forward().whenCompleteOrCancel(() {
      if (!_disposed && mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _clock.dispose();
    widget.onDone();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const AbsorbPointer(
    key: Key('tenturaSheetCloseTapShield'),
    child: SizedBox.expand(),
  );
}

/// Swallows taps on [child] from the moment its route starts closing.
///
/// The route's own pointer block only takes effect on the next frame, so the
/// second tap of a fast double click (both taps before that frame) used to
/// reach the closing sheet's button again; its `Navigator.pop` then popped
/// the page under the sheet (#684). This checks the route at hit-test time.
class _AbsorbTapsWhileClosing extends SingleChildRenderObjectWidget {
  const _AbsorbTapsWhileClosing({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAbsorbTapsWhileClosing(ModalRoute.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAbsorbTapsWhileClosing renderObject,
  ) {
    renderObject.route = ModalRoute.of(context);
  }
}

class _RenderAbsorbTapsWhileClosing extends RenderProxyBox {
  _RenderAbsorbTapsWhileClosing(this.route);

  ModalRoute<Object?>? route;

  bool get _closing {
    final r = route;
    if (r == null) return false;
    return !r.isActive || r.animation?.status == AnimationStatus.reverse;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => _closing
      ? size.contains(position)
      : super.hitTest(result, position: position);
}

/// Returns keyboard focus to [trigger] when it is a still-mounted control;
/// otherwise clears focus, so a text field focused before the sheet does not
/// grab keys (or reopen the soft keyboard) after it closes.
void _restoreFocusAfterSheet(FocusNode? trigger) {
  final triggerContext = trigger?.context;
  if (trigger != null &&
      trigger is! FocusScopeNode &&
      triggerContext != null &&
      triggerContext.mounted &&
      trigger.canRequestFocus &&
      triggerContext.findAncestorStateOfType<EditableTextState>() == null) {
    trigger.requestFocus();
    return;
  }
  FocusManager.instance.primaryFocus?.unfocus();
}

/// Closes the enclosing sheet route on Escape when keyboard focus is outside
/// it. With focus inside, the route's own [DismissIntent] handling runs
/// instead (so the key is never handled twice).
class _EscapeDismissesSheet extends StatefulWidget {
  const _EscapeDismissesSheet({required this.child});

  final Widget child;

  @override
  State<_EscapeDismissesSheet> createState() => _EscapeDismissesSheetState();
}

class _EscapeDismissesSheetState extends State<_EscapeDismissesSheet> {
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final route = _route;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted ||
        route == null ||
        !route.isCurrent ||
        !route.barrierDismissible ||
        FocusScope.of(context, createDependency: false).hasFocus) {
      return false;
    }
    route.navigator?.maybePop();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
