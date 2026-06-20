import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class BeaconDeleteDialog extends StatelessWidget {
  static Future<bool?> show(
    BuildContext context, {
    required BeaconLifecycle lifecycle,
    required bool hasEverHadCommitter,
  }) =>
      showAdaptiveDialog(
        context: context,
        builder: (_) => BeaconDeleteDialog(
          lifecycle: lifecycle,
          hasEverHadCommitter: hasEverHadCommitter,
        ),
      );

  const BeaconDeleteDialog({
    required this.lifecycle,
    required this.hasEverHadCommitter,
    super.key,
  });

  final BeaconLifecycle lifecycle;
  final bool hasEverHadCommitter;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    if (hasEverHadCommitter) {
      return AlertDialog.adaptive(
        title: Text(l10n.beaconDeleteBlockedTitle),
        content: Text(l10n.beaconDeleteBlockedBody),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: Text(l10n.buttonOk),
          ),
        ],
      );
    }
    final (title, body) = switch (lifecycle) {
      BeaconLifecycle.draft => (
          l10n.beaconDeleteDraftTitle,
          l10n.beaconDeleteDraftBody,
        ),
      BeaconLifecycle.open => (
          l10n.beaconDeleteOpenTitle,
          l10n.beaconDeleteOpenBody,
        ),
      _ => (
          l10n.confirmBeaconRemoval,
          l10n.beaconDeleteGenericBody,
        ),
    };
    return AlertDialog.adaptive(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.buttonDelete),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonCancel),
        ),
      ],
    );
  }
}
