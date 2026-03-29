import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

class CommitmentMessageDialog extends StatefulWidget {
  const CommitmentMessageDialog({
    required this.title,
    required this.hintText,
    this.initialText = '',
    super.key,
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String hintText,
    String initialText = '',
  }) =>
      showAdaptiveDialog<String>(
        context: context,
        builder: (_) => CommitmentMessageDialog(
          title: title,
          hintText: hintText,
          initialText: initialText,
        ),
      );

  final String title;
  final String hintText;
  final String initialText;

  @override
  State<CommitmentMessageDialog> createState() =>
      _CommitmentMessageDialogState();
}

class _CommitmentMessageDialogState extends State<CommitmentMessageDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      title: Text(widget.title),
      content: TextField(
        autofocus: true,
        controller: _controller,
        maxLines: 3,
        decoration: InputDecoration(hintText: widget.hintText),
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isNotEmpty) {
              Navigator.of(context).pop(text);
            }
          },
          child: Text(l10n.buttonOk),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonCancel),
        ),
      ],
    );
  }
}
