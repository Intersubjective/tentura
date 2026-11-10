import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Confirms removing a pending invite: `true` removes it; Keep invite (or
/// dismissing the dialog) returns `null`.
class InvitationRemoveDialog extends StatelessWidget {
  static Future<bool?> show(BuildContext context) => showAdaptiveDialog(
    context: context,
    builder: (_) => const InvitationRemoveDialog(),
  );

  const InvitationRemoveDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      title: Text(l10n.confirmInvitationRemovalTitle),
      content: Text(l10n.confirmInvitationRemovalBody),
      actions: [
        // Its own key so the verb matches the title in every locale (#1074).
        TextButton(
          style: TextButton.styleFrom(foregroundColor: context.tt.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.buttonRemoveInvite),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonKeepInvite),
        ),
      ],
    );
  }
}
