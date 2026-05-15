import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Edit viewer (or target) next-move text via room API.
Future<void> showBeaconRoomNextMoveSheet(
  BuildContext context, {
  required String beaconId,
  required String targetUserId,
  VoidCallback? onSaved,
}) async {
  final l10n = L10n.of(context)!;
  final roomCase = GetIt.I<BeaconRoomCase>();
  final controller = TextEditingController();
  try {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Padding(
              padding: EdgeInsets.only(
                left: kSpacingSmall,
                right: kSpacingSmall,
                top: kSpacingMedium,
                bottom: bottom + kSpacingMedium,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.beaconRoomYouStripEditNextMove,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: kSpacingSmall),
                  TextField(
                    controller: controller,
                    onChanged: (_) => setState(() {}),
                    maxLines: 4,
                    minLines: 2,
                    decoration: InputDecoration(
                      hintText: l10n.beaconRoomYouStripNextMoveLabel,
                    ),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: kSpacingMedium),
                  FilledButton(
                    onPressed: controller.text.trim().isEmpty
                        ? null
                        : () => Navigator.of(ctx).pop(true),
                    child: Text(
                      MaterialLocalizations.of(ctx).saveButtonLabel,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (ok != true || !context.mounted) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    await roomCase.participantSetNextMove(
      beaconId: beaconId,
      targetUserId: targetUserId,
      nextMoveText: text,
      nextMoveSource: BeaconNextMoveSourceBits.self,
    );
    if (context.mounted) {
      onSaved?.call();
    }
  } finally {
    controller.dispose();
  }
}
