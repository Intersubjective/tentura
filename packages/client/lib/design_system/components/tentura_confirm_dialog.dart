import 'package:flutter/material.dart';

import '../tentura_tokens.dart';

/// Adaptive confirm/cancel dialog using [AlertDialog.adaptive] and theme typography.
///
/// By default the confirm action is the filled (emphasized) button. For discard
/// / leave-without-saving flows set [emphasizeCancel] so "keep editing" is the
/// obvious primary action and the destructive confirm stays secondary.
class TenturaConfirmDialog extends StatelessWidget {
  const TenturaConfirmDialog({
    required this.title,
    required this.content,
    this.confirmLabel,
    this.cancelLabel,
    this.emphasizeCancel = false,
    super.key,
  });

  final String title;
  final String content;
  final String? confirmLabel;
  final String? cancelLabel;

  /// When true, the cancel/"keep" action uses [FilledButton] and confirm uses
  /// [TextButton] (recommended for leave-without-saving dialogs).
  final bool emphasizeCancel;

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String content,
    String? confirmLabel,
    String? cancelLabel,
    bool emphasizeCancel = false,
    bool useRootNavigator = false,
  }) =>
      showAdaptiveDialog<bool>(
        context: context,
        useRootNavigator: useRootNavigator,
        builder: (_) => TenturaConfirmDialog(
          title: title,
          content: content,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          emphasizeCancel: emphasizeCancel,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    final tt = Theme.of(context).extension<TenturaTokens>();
    final cancelText = cancelLabel ?? l10n.cancelButtonLabel;
    final confirmText = confirmLabel ?? l10n.okButtonLabel;

    final Widget cancelButton;
    final Widget confirmButton;
    if (emphasizeCancel) {
      cancelButton = FilledButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(cancelText),
      );
      confirmButton = TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(confirmText),
      );
    } else {
      cancelButton = TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(cancelText),
      );
      confirmButton = FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(confirmText),
      );
    }

    return AlertDialog.adaptive(
      constraints: BoxConstraints(maxWidth: tt?.contentMaxWidth ?? 560),
      title: Text(title),
      content: Text(
        content,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      // Trailing action is the emphasized one (Material convention).
      actions: emphasizeCancel
          ? [confirmButton, cancelButton]
          : [cancelButton, confirmButton],
    );
  }
}
