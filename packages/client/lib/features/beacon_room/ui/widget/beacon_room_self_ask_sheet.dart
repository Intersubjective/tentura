import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';
import 'package:tentura/features/coordination_item/ui/widget/ask_composer_fields.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Creates a self-targeted, immediately accepted coordination Ask (Self-Ask).
Future<void> showBeaconRoomSelfAskSheet(
  BuildContext context, {
  required String beaconId,
  AskComposerSeed? seed,
  VoidCallback? onSaved,
}) async {
  final l10n = L10n.of(context)!;
  final roomCase = GetIt.I<BeaconRoomCase>();
  final titleController = TextEditingController(text: seed?.initialTitle ?? '');
  final bodyController = TextEditingController(text: seed?.initialBody ?? '');
  final linkedMessageId = seed?.linkedMessageId;
  final messagePreview = seed?.messagePreview;
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
            final canSubmit =
                AskComposerFields.canSubmit(bodyController, submitting);
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
                    l10n.beaconRoomSelfAskSheetPrompt,
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
                  const SizedBox(height: kSpacingMedium),
                  FilledButton(
                    onPressed: !canSubmit
                        ? null
                        : () async {
                            setState(() => submitting = true);
                            try {
                              await roomCase.createSelfAsk(
                                beaconId: beaconId,
                                title: titleController.text.trim(),
                                body: bodyController.text.trim(),
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
