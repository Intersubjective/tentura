import 'dart:async';

import 'package:flutter/material.dart';

/// Keeps sheet feedback above the modal barrier without changing the sheet's
/// content-sized layout. The transparent scaffold fills the route; its body
/// retains the original sheet/dialog layout and outside-tap dismissal.
class TenturaSheetSnackBarHost extends StatelessWidget {
  const TenturaSheetSnackBarHost({
    required this.child,
    required this.isDismissible,
    super.key,
  });

  final Widget child;
  final bool isDismissible;

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isDismissible
                ? () {
                    if (ModalRoute.of(context)?.isCurrent ?? false) {
                      Navigator.of(context).maybePop();
                    }
                  }
                : null,
            child: const SizedBox.expand(),
          ),
          // The host Scaffold registers a DismissIntent action of its own that
          // answers Escape from a focused text field and does nothing (no
          // drawer). This action sits closer to the focus and routes Escape to
          // the route's dismissal, as a sheet without a host does.
          Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  if (isDismissible &&
                      (ModalRoute.of(context)?.isCurrent ?? false)) {
                    unawaited(Navigator.of(context).maybePop());
                  }
                  return null;
                },
              ),
            },
            child: child,
          ),
        ],
      ),
    ),
  );
}
