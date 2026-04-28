import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';

/// Author: pick per-commit coordination response.
Future<void> showCoordinationResponseBottomSheet({
  required BuildContext context,
  required String commitUserTitle,
  required void Function(int responseTypeSmallint) onPick,
}) async {
  final l10n = L10n.of(context)!;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '$commitUserTitle — ${l10n.labelSetCoordinationResponse}',
              style: Theme.of(ctx).textTheme.titleSmall,
            ),
          ),
          Flexible(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final t in CoordinationResponseType.values)
                  ListTile(
                    title: Text(
                      coordinationResponseLabel(l10n, t) ?? '',
                    ),
                    subtitle: Text(
                      t == CoordinationResponseType.notSuitable
                          ? l10n.coordinationResponseRoomNoAdmission
                          : l10n.coordinationResponseRoomAdmits,
                      style: TenturaText.body(
                        t == CoordinationResponseType.notSuitable
                            ? Theme.of(ctx).colorScheme.error
                            : Theme.of(ctx).colorScheme.tertiary,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      onPick(t.smallintValue);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Author: override beacon-level coordination status (manual).
Future<void> showBeaconCoordinationStatusBottomSheet({
  required BuildContext context,
  required void Function(int statusSmallint) onPick,
}) async {
  final l10n = L10n.of(context)!;
  final options = <(int, String)>[
    (
      BeaconCoordinationStatus.commitmentsWaitingForReview.smallintValue,
      l10n.coordinationWaitingForReview,
    ),
    (
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded.smallintValue,
      l10n.coordinationMoreHelpNeeded,
    ),
    (
      BeaconCoordinationStatus.enoughHelpCommitted.smallintValue,
      l10n.coordinationEnoughHelp,
    ),
  ];
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              l10n.coordinationSetOverallStatus,
              style: Theme.of(ctx).textTheme.titleSmall,
            ),
          ),
          Flexible(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final o in options)
                  ListTile(
                    title: Text(o.$2),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      onPick(o.$1);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
