import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

Future<String?> _showInboxNoteDialog(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  final l10n = L10n.of(context)!;
  final controller = TextEditingController();

  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          maxLines: 4,
          maxLength: 200,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop<String>(),
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

/// Returns optional rejection message, or null if cancelled.
Future<String?> showRejectionDialog(BuildContext context) {
  final l10n = L10n.of(context)!;
  return _showInboxNoteDialog(
    context,
    title: l10n.rejectionDialogTitle,
    hint: l10n.rejectionDialogHint,
  );
}

/// Inbox card dismiss (X) — same reject action, inbox-oriented copy.
Future<String?> showInboxDismissDialog(BuildContext context) {
  final l10n = L10n.of(context)!;
  return _showInboxNoteDialog(
    context,
    title: l10n.inboxDismissDialogTitle,
    hint: l10n.inboxDismissDialogHint,
  );
}
