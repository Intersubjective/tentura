import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/code_unit_length_formatter.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';

/// Asks "for whom is this invite?" (required) — the name is the issuer's
/// private contact name for the future joiner, never shown to the invitee.
/// Also reused to edit the name of a pending invite.
class InvitationAddresseeDialog extends StatefulWidget {
  const InvitationAddresseeDialog._({
    required this.initialName,
    required this.isEdit,
  });

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

  // On a character boundary, never half an emoji (#356).
  late final _controller = TextEditingController(
    text: CodeUnitLengthLimitingTextInputFormatter.truncate(
      widget.initialName,
      kTitleMaxLength,
    ),
  );

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
    final theme = Theme.of(context);
    final tt = context.tt;
    final muted = TenturaText.bodySmall(theme.colorScheme.onSurfaceVariant);
    return AlertDialog(
      scrollable: true,
      insetPadding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.sectionGap,
      ),
      title: Text(
        widget.isEdit
            ? l10n.invitationAddresseeEditTitle
            : l10n.invitationAddresseeTitle,
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.isEdit) ...[
              Text(
                l10n.invitationDualPurposeBody,
                style: muted,
              ),
              SizedBox(height: tt.rowGap),
              Text(
                l10n.invitationSingleUseBody,
                style: muted,
              ),
              SizedBox(height: tt.sectionGap),
            ],
            Text(
              l10n.invitationAddresseeFieldLabel,
              style: theme.textTheme.bodyMedium,
            ),
            SizedBox(height: tt.tightGap),
            Text(
              l10n.invitationAddresseeHelper,
              style: muted,
            ),
            SizedBox(height: tt.rowGap),
            TextFormField(
              controller: _controller,
              autofocus: true,
              maxLength: kTitleMaxLength,
              // Code units, as the validator and the server count the name
              // (#356): maxLength alone counts characters, so an emoji fit
              // here and was then refused as too long.
              inputFormatters: const [
                CodeUnitLengthLimitingTextInputFormatter(kTitleMaxLength),
              ],
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) => Text(
                    '${_controller.text.length}/$maxLength',
                    style: TenturaText.withTabular(
                      TenturaText.bodySmall(context.tt.textMuted),
                    ),
                  ),
              validator: (value) => displayNameValidator(l10n, value?.trim()),
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
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
