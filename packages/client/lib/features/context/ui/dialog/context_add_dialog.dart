import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';

class ContextAddDialog extends StatefulWidget {
  static Future<String?> show(BuildContext context) =>
      showAdaptiveDialog<String>(
        context: context,
        builder: (_) => const ContextAddDialog(),
      );

  const ContextAddDialog({super.key});

  @override
  State<ContextAddDialog> createState() => _ContextAddDialogState();
}

class _ContextAddDialogState extends State<ContextAddDialog>
    with StringInputValidator {
  final _controller = TextEditingController();

  late final _l10n = L10n.of(context)!;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text(_l10n.addNewTopic),
    content: TextFormField(
      autofocus: true,
      controller: _controller,
      maxLength: kTitleMaxLength,
      validator: (value) => titleValidator(_l10n, value),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: Text(_l10n.buttonOk),
      ),
      TextButton(
        onPressed: Navigator.of(context).pop,
        child: Text(_l10n.buttonCancel),
      ),
    ],
  );
}
