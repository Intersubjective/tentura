import 'package:flutter/material.dart';

class OnChatClearDialog extends StatelessWidget {
  static Future<bool?> show(BuildContext context) => showAdaptiveDialog<bool>(
    context: context,
    builder: (_) => const OnChatClearDialog(),
  );

  const OnChatClearDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: const Text(
      'Are you sure you want to delete all messages from this chat?',
    ),
    actions: [
      // Clear
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Remove'),
      ),

      // Cancel
      TextButton(
        onPressed: Navigator.of(context).pop,
        child: const Text('Cancel'),
      ),
    ],
  );
}
