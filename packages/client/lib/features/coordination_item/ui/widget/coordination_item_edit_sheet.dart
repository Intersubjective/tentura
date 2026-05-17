import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/beacon_view/ui/bloc/items_tab_cubit.dart';

String _editSheetTitle(L10n l10n, CoordinationItem item) => switch (item.kind) {
      CoordinationItemKind.blocker => l10n.coordinationBlockerCardLabel,
      CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
      CoordinationItemKind.plan => item.isPlanStep
          ? l10n.coordinationPlanStepCardLabel
          : l10n.coordinationPlanCardLabel,
      CoordinationItemKind.resolution => l10n.coordinationResolutionCardLabel,
    };

/// In-place edit for a published coordination item (open or accepted).
Future<void> showCoordinationItemEditSheet(
  BuildContext context, {
  required CoordinationItem item,
  VoidCallback? onSaved,
}) async {
  final l10n = L10n.of(context)!;
  final titleController = TextEditingController(text: item.title);
  final bodyController = TextEditingController(text: item.body);
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
                    _editSheetTitle(l10n, item),
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: kSpacingSmall),
                  TextField(
                    controller: titleController,
                    onChanged: (_) => setState(() {}),
                    maxLines: 2,
                    minLines: 1,
                    textInputAction: TextInputAction.next,
                    enabled: !submitting,
                    autofocus: true,
                  ),
                  const SizedBox(height: kSpacingSmall),
                  TextField(
                    controller: bodyController,
                    onChanged: (_) => setState(() {}),
                    maxLines: 6,
                    minLines: 3,
                    enabled: !submitting,
                  ),
                  const SizedBox(height: kSpacingMedium),
                  FilledButton(
                    onPressed: !canSubmit
                        ? null
                        : () async {
                            setState(() => submitting = true);
                            try {
                              await ctx.read<ItemsTabCubit>().updateItem(
                                    itemId: item.id,
                                    title: titleController.text.trim(),
                                    body: bodyController.text.trim(),
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
