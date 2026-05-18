import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';
import 'package:tentura/features/coordination_item/ui/widget/ask_composer_fields.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

List<BeaconParticipant> participantsForPromiseTargetPicker({
  required List<BeaconParticipant> participants,
  required String myUserId,
  required bool isAuthorOrSteward,
}) {
  final admitted = isAuthorOrSteward
      ? participants
          .where((p) =>
              p.roomAccess == RoomAccessBits.admitted ||
              p.status == BeaconParticipantStatusBits.candidate ||
              p.status == BeaconParticipantStatusBits.offeredHelp)
          .toList()
      : participants
          .where((p) => p.roomAccess == RoomAccessBits.admitted)
          .toList();
  return admitted.where((p) => p.userId != myUserId).toList();
}

String _targetLabel(L10n l10n, BeaconParticipant p) {
  final t = p.userTitle.trim();
  if (t.isNotEmpty) return t;
  return p.userId.length <= 16 ? p.userId : '${p.userId.substring(0, 14)}…';
}

/// Creates a published coordination promise (creator commits; target must accept).
Future<void> showBeaconRoomPromiseSheet(
  BuildContext context, {
  required String beaconId,
  required List<BeaconParticipant> participants,
  required String myUserId,
  required bool isAuthorOrSteward,
  AskComposerSeed? seed,
  VoidCallback? onSaved,
}) async {
  final l10n = L10n.of(context)!;
  final roomCase = GetIt.I<BeaconRoomCase>();
  final titleController = TextEditingController(text: seed?.initialTitle ?? '');
  final bodyController = TextEditingController(text: seed?.initialBody ?? '');
  final linkedMessageId = seed?.linkedMessageId;
  final messagePreview = seed?.messagePreview;

  final targets = participantsForPromiseTargetPicker(
    participants: participants,
    myUserId: myUserId,
    isAuthorOrSteward: isAuthorOrSteward,
  );
  if (targets.isEmpty) return;

  var targetUserId = targets.first.userId;

  try {
    var submitting = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
            final canSubmit = AskComposerFields.canSubmit(bodyController, submitting) &&
                targetUserId.isNotEmpty;
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
                    l10n.coordinationCreatePromiseSheetPrompt,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: kSpacingSmall),
                  AskComposerFields(
                    l10n: l10n,
                    titleController: titleController,
                    bodyController: bodyController,
                    submitting: submitting,
                    messagePreview: messagePreview,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: kSpacingSmall),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>(targetUserId),
                    initialValue: targetUserId,
                    decoration: InputDecoration(
                      labelText: l10n.coordinationPromiseTargetPickerLabel,
                    ),
                    items: [
                      for (final p in targets)
                        DropdownMenuItem(
                          value: p.userId,
                          child: Text(_targetLabel(l10n, p)),
                        ),
                    ],
                    onChanged: submitting
                        ? null
                        : (v) => setState(() => targetUserId = v ?? targetUserId),
                  ),
                  const SizedBox(height: kSpacingMedium),
                  FilledButton(
                    onPressed: !canSubmit
                        ? null
                        : () async {
                            setState(() => submitting = true);
                            try {
                              await roomCase.createPromise(
                                beaconId: beaconId,
                                title: titleController.text.trim(),
                                body: bodyController.text.trim(),
                                targetPersonId: targetUserId,
                                linkedMessageId: linkedMessageId,
                              );
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop(true);
                              }
                            } on Object catch (_) {
                              if (ctx.mounted) {
                                setState(() => submitting = false);
                              }
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(MaterialLocalizations.of(ctx).saveButtonLabel),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (ok == true && context.mounted) {
      onSaved?.call();
    }
  } finally {
    titleController.dispose();
    bodyController.dispose();
  }
}
