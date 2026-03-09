import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

class ContextRemoveDialog extends StatelessWidget {
  static Future<bool?> show(
    BuildContext context, {
    required String contextName,
  }) => showAdaptiveDialog<bool>(
    context: context,
    builder: (_) => ContextRemoveDialog(contextName: contextName),
  );

  const ContextRemoveDialog({required this.contextName, super.key});

  final String contextName;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      title: Text(l10n.labelConfirmation),
      content: Text(l10n.topicRemovalMessage(contextName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Yes'),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
