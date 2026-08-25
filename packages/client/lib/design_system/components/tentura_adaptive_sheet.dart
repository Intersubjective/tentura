import 'package:flutter/material.dart';

import '../tentura_tokens.dart';
import '../tentura_window_class.dart';
import 'tentura_modal_bottom_sheet_route.dart';

/// Shows app-owned modal content as a bottom sheet on compact windows and as a
/// centered constrained dialog on regular/expanded windows.
///
/// Compact sheets use [TenturaModalBottomSheetRoute] so drag-to-dismiss goes
/// through [Navigator.maybePop] and respects [TenturaSheetDismissGuard].
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
  final T? result;
  if (windowClass == WindowClass.compact) {
    final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
    final localizations = MaterialLocalizations.of(context);
    result = await navigator.push<T>(
      TenturaModalBottomSheetRoute<T>(
        builder: builder,
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
              child: child,
            ),
          ),
        );
      },
    );
  }
  FocusManager.instance.primaryFocus?.unfocus();
  return result;
}
