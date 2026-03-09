import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

class BeaconDeleteDialog extends StatelessWidget {
  static Future<bool?> show(BuildContext context) => showAdaptiveDialog(
    context: context,
    builder: (_) => const BeaconDeleteDialog(),
  );

  const BeaconDeleteDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      title: Text(l10n.confirmBeaconRemoval),
      actions: [
        // Delete
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.buttonDelete),
        ),

        // Cancel
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonCancel),
        ),
      ],
    );
  }
}
