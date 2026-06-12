import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';

/// Asks "for whom is this invite?" (required) — the name is the issuer's
/// private contact name for the future joiner, never shown to the invitee.
/// Also reused to edit the name of a pending invite.
class InvitationAddresseeDialog extends StatefulWidget {
  const InvitationAddresseeDialog._({required this.initialName, required this.isEdit});

  final String initialName;
  final bool isEdit;

  /// Returns the trimmed addressee name, or null when cancelled.
  static Future<String?> show(
    BuildContext context, {
    String initialName = '',
    bool isEdit = false,
  }) => showDialog<String>(
    context: context,
    builder: (_) => InvitationAddresseeDialog._(
      initialName: initialName,
      isEdit: isEdit,
    ),
  );

  @override
  State<InvitationAddresseeDialog> createState() =>
      _InvitationAddresseeDialogState();
}

class _InvitationAddresseeDialogState extends State<InvitationAddresseeDialog>
    with StringInputValidator {
  final _formKey = GlobalKey<FormState>();

  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog(
      title: Text(
        widget.isEdit
            ? l10n.invitationAddresseeEditTitle
            : l10n.invitationAddresseeTitle,
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: kTitleMaxLength,
          decoration: InputDecoration(
            labelText: l10n.invitationAddresseeFieldLabel,
          ),
          validator: (value) => displayNameValidator(l10n, value?.trim()),
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.buttonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.isEdit ? l10n.buttonSave : l10n.buttonCreate),
        ),
      ],
    );
  }
}
