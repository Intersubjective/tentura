import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/string_input_formatter.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';

class BeaconAddTagDialog extends StatefulWidget {
  static Future<String?> show(BuildContext context) =>
      showAdaptiveDialog<String>(
        context: context,
        builder: (_) => const BeaconAddTagDialog(),
      );

  const BeaconAddTagDialog({super.key});

  @override
  State<BeaconAddTagDialog> createState() => _BeaconAddTagDialogState();
}

class _BeaconAddTagDialogState extends State<BeaconAddTagDialog>
    with StringInputValidator, StringInputFormatter {
  final _tagController = TextEditingController();

  late final _textTheme = Theme.of(context).textTheme;

  late final _l10n = L10n.of(context)!;

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Text(_l10n.addTagText),
      titleTextStyle: _textTheme.headlineLarge,
      content: TextFormField(
        autofocus: true,
        controller: _tagController,
        decoration: InputDecoration(
          hintText: _l10n.enterTagNameHint,
          prefixIcon: const Icon(Icons.tag),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(tagNameRegExp),
        ],
        maxLength: kTitleMaxLength,
        validator: (value) => titleValidator(_l10n, value),
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      ),
      contentTextStyle: _textTheme.bodyMedium,
      actions: [
        // Yes
        TextButton(
          onPressed: () => Navigator.of(context).pop(_tagController.text),
          child: Text(_l10n.buttonYes),
        ),

        // Cancel
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(_l10n.buttonCancel),
        ),
      ],
    );
  }
}
