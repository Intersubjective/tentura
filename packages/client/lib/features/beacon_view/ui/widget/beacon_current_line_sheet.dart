import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

/// Sets the beacon room [current line] (synced via coordination updatePlan).
Future<void> showBeaconCurrentLineSheet(
  BuildContext context, {
  required String beaconId,
  required String initialText,
  VoidCallback? onSaved,
}) async {
  final l10n = L10n.of(context)!;
  final coordinationCase = GetIt.I<CoordinationItemCase>();
  final titleController = TextEditingController(text: initialText);
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
                titleController.text.trim().isNotEmpty && !submitting;
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
                    l10n.beaconHudEditCurrentLineTitle,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: kSpacingSmall),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      hintText: l10n.beaconRoomStripCurrentLineLabel,
                    ),
                    onChanged: (_) => setState(() {}),
                    maxLines: 6,
                    minLines: 3,
                    textInputAction: TextInputAction.done,
                    enabled: !submitting,
                    autofocus: true,
                  ),
                  const SizedBox(height: kSpacingMedium),
                  FilledButton(
                    onPressed: !canSubmit
                        ? null
                        : () async {
                            setState(() => submitting = true);
                            try {
                              await coordinationCase.updatePlan(
                                beaconId: beaconId,
                                title: titleController.text.trim(),
                              );
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop(true);
                              }
                            } on Object catch (e) {
                              if (ctx.mounted) {
                                setState(() => submitting = false);
                                final locale = L10n.of(ctx)?.localeName;
                                showSnackBar(
                                  ctx,
                                  isError: true,
                                  text: switch (e) {
                                    final Localizable l => l.toL10n(locale),
                                    _ => e.toString(),
                                  },
                                );
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
  }
}
