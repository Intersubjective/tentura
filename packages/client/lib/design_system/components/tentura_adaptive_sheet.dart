import 'package:flutter/material.dart';

import '../tentura_tokens.dart';
import '../tentura_window_class.dart';

/// Shows app-owned modal content as a bottom sheet on compact windows and as a
/// centered constrained dialog on regular/expanded windows.
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
}) {
  final windowClass = windowClassForWidth(MediaQuery.sizeOf(context).width);
  if (windowClass == WindowClass.compact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      useRootNavigator: useRootNavigator,
      useSafeArea: useSafeArea,
      enableDrag: enableDrag,
      isDismissible: isDismissible,
      builder: builder,
    );
  }

  return showDialog<T>(
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
