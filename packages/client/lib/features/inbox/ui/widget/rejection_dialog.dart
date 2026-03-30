import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

/// Returns optional rejection message, or null if cancelled.
Future<String?> showRejectionDialog(BuildContext context) async {
  final l10n = L10n.of(context)!;
  final controller = TextEditingController();

  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.rejectionDialogTitle),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: l10n.rejectionDialogHint,
            border: const OutlineInputBorder(),
          ),
          maxLines: 4,
          maxLength: 200,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop<String>(null),
            child: Text(l10n.buttonCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop<String>(controller.text.trim()),
            child: Text(l10n.buttonOk),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}
