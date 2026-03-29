import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

class OnChatClearDialog extends StatelessWidget {
  static Future<bool?> show(BuildContext context) => showAdaptiveDialog<bool>(
    context: context,
    builder: (_) => const OnChatClearDialog(),
  );

  const OnChatClearDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      title: Text(l10n.chatClearConfirmTitle),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.buttonRemove),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonCancel),
        ),
      ],
    );
  }
}
