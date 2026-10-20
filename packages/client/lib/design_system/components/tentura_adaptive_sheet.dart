import 'package:flutter/material.dart';
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
  final T? result;
  if (windowClass == WindowClass.compact) {
    final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
    final localizations = MaterialLocalizations.of(context);
    result = await navigator.push<T>(
      TenturaModalBottomSheetRoute<T>(
        builder: (sheetContext) => _EscapeDismissesSheet(
          child: builder(sheetContext),
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

        return SafeArea(
          child: Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: resolvedMaxWidth,
                maxHeight: maxHeight,
              ),
              child: _EscapeDismissesSheet(child: child),
            ),
          ),
        );
      },
    );
  }
  _restoreFocusAfterSheet(trigger);
  return result;
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
