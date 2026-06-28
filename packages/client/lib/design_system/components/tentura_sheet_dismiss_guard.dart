import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import 'tentura_confirm_dialog.dart';

/// Optional copy for the discard confirmation shown when closing a dirty sheet.
class TenturaSheetDiscardCopy {
  const TenturaSheetDiscardCopy({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;

  factory TenturaSheetDiscardCopy.composer(L10n l10n) =>
      TenturaSheetDiscardCopy(
        title: l10n.composerDiscardTitle,
        body: l10n.composerDiscardBody,
        confirmLabel: l10n.composerDiscardConfirm,
        cancelLabel: l10n.composerDiscardKeepEditing,
      );
}

/// Wraps modal sheet content so barrier tap and system back respect [isDirty].
///
/// When clean, dismiss closes immediately. When dirty, shows a discard confirm
/// dialog before popping.
class TenturaSheetDismissGuard extends StatelessWidget {
  const TenturaSheetDismissGuard({
    required this.isDirty,
    required this.child,
    this.useRootNavigator = false,
    this.discardCopy,
    super.key,
  });

  final bool isDirty;
  final Widget child;
  final bool useRootNavigator;
  final TenturaSheetDiscardCopy? discardCopy;

  /// Programmatic dismiss (Cancel button, Escape). Same logic as barrier/back.
  static Future<void> requestClose(
    BuildContext context, {
    required bool isDirty,
    bool useRootNavigator = false,
    TenturaSheetDiscardCopy? discardCopy,
  }) async {
    if (!isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final l10n = L10n.of(context)!;
    final copy = discardCopy ?? TenturaSheetDiscardCopy.composer(l10n);
    final confirmed = await TenturaConfirmDialog.show(
      context: context,
      title: copy.title,
      content: copy.body,
      confirmLabel: copy.confirmLabel,
      cancelLabel: copy.cancelLabel,
      useRootNavigator: useRootNavigator,
    );
    if ((confirmed ?? false) && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await requestClose(
          context,
          isDirty: isDirty,
          useRootNavigator: useRootNavigator,
          discardCopy: discardCopy,
        );
      },
      child: child,
    );
  }
}
