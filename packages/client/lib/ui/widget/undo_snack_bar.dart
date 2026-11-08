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
  BuildContext? context, {
  required String text,
  required VoidCallback onUndo,
  Duration duration = kUndoSnackBarDuration,
  AnimationStyle? animationStyle,
  ScaffoldMessengerState? messenger,
  String? undoLabel,
}) {
  final resolved =
      messenger ??
      (context == null ? null : ScaffoldMessenger.maybeOf(context)) ??
      snackbarKey.currentState;
  if (resolved == null) return null;
  final resolvedUndoLabel =
      undoLabel ?? (context == null ? null : L10n.of(context)?.peopleTagsUndo);
  if (resolvedUndoLabel == null) return null;
  var undone = false;
  resolved.clearSnackBars();
  return resolved.showSnackBar(
    snackBarAnimationStyle: animationStyle,
    SnackBar(
      content: Text(text),
      duration: duration,
      // Flutter pins any bar that has an action unless told otherwise (#470).
      persist: false,
      action: SnackBarAction(
        label: resolvedUndoLabel,
        onPressed: () {
          if (undone) return;
          undone = true;
          onUndo();
        },
      ),
    ),
  );
}
