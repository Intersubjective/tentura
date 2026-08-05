import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/ui/l10n/l10n.dart';

class BeaconDeleteDialog extends StatelessWidget {
  static Future<bool?> show(
    BuildContext context, {
    required BeaconStatus status,
    required bool hasEverHadCommitter,
    Future<void> Function()? onArchive,
  }) =>
      showAdaptiveDialog(
        context: context,
        builder: (_) => BeaconDeleteDialog(
          status: status,
          hasEverHadCommitter: hasEverHadCommitter,
          onArchive: onArchive,
        ),
      );

  const BeaconDeleteDialog({
    required this.status,
    required this.hasEverHadCommitter,
    this.onArchive,
    super.key,
  });

  final BeaconStatus status;
  final bool hasEverHadCommitter;
  final Future<void> Function()? onArchive;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    if (hasEverHadCommitter) {
      return AlertDialog.adaptive(
        title: Text(l10n.beaconDeleteBlockedTitle),
        content: Text(l10n.beaconDeleteBlockedBody),
        actions: [
          if (onArchive != null)
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await onArchive!();
              },
              child: Text(l10n.myWorkArchive),
            ),
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: Text(l10n.buttonOk),
          ),
        ],
      );
    }
    final (title, body) = switch (status) {
      BeaconStatus.draft => (
          l10n.beaconDeleteDraftTitle,
          l10n.beaconDeleteDraftBody,
        ),
      BeaconStatus.open ||
      BeaconStatus.needsMoreHelp ||
      BeaconStatus.enoughHelp => (
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
