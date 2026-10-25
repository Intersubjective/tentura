import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// How long an Undo bar stays up unless the caller says otherwise.
const kUndoSnackBarDuration = Duration(seconds: 10);

/// Shows [text] with an Undo action that calls [onUndo] once.
///
/// Stays [duration] (10 s, longer than an ordinary bar so the person has time
/// to notice what happened and take it back).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showUndoSnackBar(
  BuildContext context, {
  required String text,
  required VoidCallback onUndo,
  Duration duration = kUndoSnackBarDuration,
  AnimationStyle? animationStyle,
}) {
  final messenger =
      ScaffoldMessenger.maybeOf(context) ?? snackbarKey.currentState;
  if (messenger == null) return null;
  var undone = false;
  messenger.clearSnackBars();
  return messenger.showSnackBar(
    snackBarAnimationStyle: animationStyle,
    SnackBar(
      content: Text(text),
      duration: duration,
      // Flutter pins any bar that has an action unless told otherwise (#470).
      persist: false,
      action: SnackBarAction(
        label: L10n.of(context)!.peopleTagsUndo,
        onPressed: () {
          if (undone) return;
          undone = true;
          onUndo();
        },
      ),
    ),
  );
}
