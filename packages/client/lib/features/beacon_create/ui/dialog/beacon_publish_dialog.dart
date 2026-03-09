import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

class BeaconPublishDialog extends StatelessWidget {
  static Future<bool?> show(BuildContext context) => showAdaptiveDialog<bool>(
    context: context,
    builder: (_) => const BeaconPublishDialog(),
  );

  const BeaconPublishDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog.adaptive(
      title: Text(l10n.confirmBeaconPublishing),
      titleTextStyle: textTheme.headlineLarge,
      content: Text(l10n.confirmBeaconPublishingHint),
      contentTextStyle: textTheme.bodyMedium,
      actions: [
        // Yes
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.buttonYes),
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
