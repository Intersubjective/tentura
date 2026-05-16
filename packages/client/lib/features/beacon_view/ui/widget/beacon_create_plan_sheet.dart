import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/items_tab_cubit.dart';

/// Creates a root coordination Plan for the beacon (title only).
Future<void> showBeaconCreatePlanSheet(
  BuildContext context, {
  VoidCallback? onSaved,
}) async {
  final l10n = L10n.of(context)!;
  final titleController = TextEditingController();
  try {
    var submitting = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
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
                    l10n.itemsTabCreatePlanSheetPrompt,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: kSpacingSmall),
                  TextField(
                    controller: titleController,
                    onChanged: (_) => setState(() {}),
                    maxLines: 2,
                    minLines: 1,
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
                              await ctx
                                  .read<ItemsTabCubit>()
                                  .createPlan(titleController.text.trim());
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
  }
}
