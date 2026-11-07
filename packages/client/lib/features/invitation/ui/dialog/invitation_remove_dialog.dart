import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

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
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.buttonRemove),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonKeepInvite),
        ),
      ],
    );
  }
}
