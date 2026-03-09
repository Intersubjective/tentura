import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

class OpinionDeleteDialog extends StatelessWidget {
  static Future<bool?> show(BuildContext context) => showAdaptiveDialog(
    context: context,
    builder: (_) => const OpinionDeleteDialog(),
  );

  const OpinionDeleteDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      title: Text(l10n.confirmOpinionRemoval),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.buttonYes),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonCancel),
        ),
      ],
    );
  }
}
