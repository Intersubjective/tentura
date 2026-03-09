import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

class OpinionPublishDialog extends StatelessWidget {
  static Future<int?> show(BuildContext context) => showAdaptiveDialog(
    context: context,
    builder: (_) => const OpinionPublishDialog(),
  );

  const OpinionPublishDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      title: Text(l10n.positiveOrNegativeOpinion),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(1),
          child: Text(l10n.positiveOpinion),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(-1),
          child: Text(l10n.negativeOpinion),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonCancel),
        ),
      ],
    );
  }
}
