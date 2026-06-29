import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

Future<String?> _showInboxNoteDialog(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  return showDialog<String>(
    context: context,
    builder: (_) => _InboxNoteDialog(
      title: title,
      hint: hint,
    ),
  );
}

class _InboxNoteDialog extends StatefulWidget {
  const _InboxNoteDialog({
    required this.title,
    required this.hint,
  });

  final String title;
  final String hint;

  @override
  State<_InboxNoteDialog> createState() => _InboxNoteDialogState();
}

class _InboxNoteDialogState extends State<_InboxNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
        maxLines: 4,
        maxLength: 200,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<String>(),
          child: Text(l10n.buttonCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop<String>(_controller.text.trim()),
          child: Text(l10n.buttonOk),
        ),
      ],
    );
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
