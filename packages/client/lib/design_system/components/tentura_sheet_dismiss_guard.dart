import 'dart:async';

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

/// Wraps modal sheet content so barrier tap, system back, and drag-to-dismiss
/// respect [isDirty].
///
/// When clean, dismiss closes immediately. When dirty, restores a mid-drag
/// sheet (if needed) and shows a discard confirm dialog before popping.
///
/// Compact sheets must be opened via [showTenturaAdaptiveSheet] (uses
/// [Navigator.maybePop] on close). Stock [showModalBottomSheet] force-pops on
/// drag and cannot be guarded.
class TenturaSheetDismissGuard extends StatefulWidget {
  const TenturaSheetDismissGuard({
    required this.isDirty,
    required this.child,
    this.useRootNavigator = false,
    this.discardCopy,
    this.canDismiss = true,
    super.key,
  });

  final bool isDirty;
  final Widget child;
  final bool useRootNavigator;
  final TenturaSheetDiscardCopy? discardCopy;
  final bool canDismiss;

  /// Programmatic dismiss (Cancel button, Escape). Same logic as barrier/back.
  static Future<void> requestClose(
    BuildContext context, {
    required bool isDirty,
    bool useRootNavigator = false,
    TenturaSheetDiscardCopy? discardCopy,
    bool canDismiss = true,
  }) async {
    if (!canDismiss) return;
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
      emphasizeCancel: true,
      useRootNavigator: useRootNavigator,
    );
    if ((confirmed ?? false) && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  State<TenturaSheetDismissGuard> createState() =>
      _TenturaSheetDismissGuardState();
}

class _TenturaSheetDismissGuardState extends State<TenturaSheetDismissGuard> {
  bool _handlingPop = false;

  Future<void> _onPopInvoked(bool didPop) async {
    if (didPop || _handlingPop) return;
    _handlingPop = true;
    try {
      // Drag-to-dismiss flings the route animation closed before maybePop
      // fails; snap the sheet back open so the confirm dialog has a host.
      final controller = ModalRoute.of(context)?.controller;
      if (controller != null && controller.value < 1.0) {
        await controller.forward();
      }
      if (!mounted) return;
      await TenturaSheetDismissGuard.requestClose(
        context,
        isDirty: widget.isDirty,
        useRootNavigator: widget.useRootNavigator,
        discardCopy: widget.discardCopy,
        canDismiss: widget.canDismiss,
      );
    } finally {
      _handlingPop = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.canDismiss && !widget.isDirty,
      onPopInvokedWithResult: (didPop, _) {
        unawaited(_onPopInvoked(didPop));
      },
      child: widget.child,
    );
  }
}
