import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';

/// Subjective profiles: rename [profile] as the viewer sees them.
/// Shows the user's self-chosen name as reference; "Reset to their name"
/// removes the contact entry so the objective name shows again.
class RenameContactDialog extends StatefulWidget {
  const RenameContactDialog._({required this.profile});

  final Profile profile;

  /// Returns true when the contact map changed (renamed or reset).
  static Future<bool?> show(BuildContext context, {required Profile profile}) =>
      showDialog<bool>(
        context: context,
        builder: (_) => RenameContactDialog._(profile: profile),
      );

  @override
  State<RenameContactDialog> createState() => _RenameContactDialogState();
}

class _RenameContactDialogState extends State<RenameContactDialog>
    with StringInputValidator {
  final _formKey = GlobalKey<FormState>();

  late final _controller = TextEditingController(
    text: widget.profile.contactName.isNotEmpty
        ? widget.profile.contactName
        : widget.profile.displayName,
  );

  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        final localeName = L10n.of(context)?.localeName;
        showSnackBar(
          context,
          text: e is Localizable ? e.toL10n(localeName) : e.toString(),
          isError: true,
          error: e,
        );
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(
      () => GetIt.I<ContactsCase>().rename(
        subjectId: widget.profile.id,
        contactName: _controller.text.trim(),
      ),
    );
  }

  Future<void> _reset() =>
      _run(() => GetIt.I<ContactsCase>().reset(subjectId: widget.profile.id));

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
      title: Text(l10n.renameContactTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.profile.handle.isEmpty
                  ? l10n.renameContactOriginalName(widget.profile.displayName)
                  : '${l10n.renameContactOriginalName(widget.profile.displayName)}'
                        ' @${widget.profile.handle}',
              style: muted,
            ),
            SizedBox(height: tt.sectionGap),
            Text(
              l10n.renameContactFieldLabel,
              style: theme.textTheme.bodyMedium,
            ),
            SizedBox(height: tt.tightGap),
            Text(
              l10n.renameContactHelper,
              style: muted,
            ),
            SizedBox(height: tt.rowGap),
            TextFormField(
              controller: _controller,
              autofocus: true,
              maxLength: kTitleMaxLength,
              validator: (value) =>
                  displayNameValidator(l10n, value?.trim()),
              onFieldSubmitted: (_) => unawaited(_save()),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.profile.contactName.isNotEmpty)
          TextButton(
            onPressed: _busy ? null : _reset,
            child: Text(l10n.renameContactReset),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.buttonCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(l10n.buttonSave),
        ),
      ],
    );
  }
}
