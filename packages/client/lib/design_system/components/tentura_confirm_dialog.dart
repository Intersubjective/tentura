import 'package:flutter/material.dart';

import '../tentura_tokens.dart';

/// Adaptive confirm/cancel dialog using [AlertDialog.adaptive] and theme typography.
class TenturaConfirmDialog extends StatelessWidget {
  const TenturaConfirmDialog({
    required this.title,
    required this.content,
    this.confirmLabel,
    this.cancelLabel,
    super.key,
  });

  final String title;
  final String content;
  final String? confirmLabel;
  final String? cancelLabel;

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String content,
    String? confirmLabel,
    String? cancelLabel,
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
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    final tt = Theme.of(context).extension<TenturaTokens>();
    return AlertDialog.adaptive(
      constraints: BoxConstraints(maxWidth: tt?.contentMaxWidth ?? 560),
      title: Text(title),
      content: Text(
        content,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel ?? l10n.cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel ?? l10n.okButtonLabel),
        ),
      ],
    );
  }
}
