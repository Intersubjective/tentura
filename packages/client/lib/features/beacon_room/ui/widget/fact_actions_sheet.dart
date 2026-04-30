import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/message/beacon_room_fact_messages.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Actions for a single fact card (modal).
Future<void> showFactActionsSheet(
  BuildContext context, {
  required RoomCubit cubit,
  required BeaconFactCard fact,
}) {
  final l10n = L10n.of(context)!;
  final rootCtx = context;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: kPaddingH.add(kPaddingSmallT),
              child: Text(
                l10n.beaconRoomFactManageSheetTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.beaconRoomFactCardActionEdit),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_showEditFactSheet(rootCtx, cubit, fact));
              },
            ),
            if (fact.visibility == BeaconFactCardVisibilityBits.room)
              ListTile(
                leading: const Icon(Icons.public_outlined),
                title: Text(l10n.beaconRoomFactCardActionMakePublic),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(
                    cubit.setFactVisibility(
                      factCardId: fact.id,
                      visibility: BeaconFactCardVisibilityBits.public,
                    ),
                  );
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(l10n.beaconRoomFactCardActionMakePrivate),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(
                    cubit.setFactVisibility(
                      factCardId: fact.id,
                      visibility: BeaconFactCardVisibilityBits.room,
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.message_outlined),
              title: Text(l10n.beaconRoomFactCardActionJumpToSource),
              enabled: fact.sourceMessageId != null && fact.sourceMessageId!.isNotEmpty,
              onTap: fact.sourceMessageId == null || fact.sourceMessageId!.isEmpty
                  ? null
                  : () {
                      final mid = fact.sourceMessageId!;
                      Navigator.pop(ctx);
                      cubit.requestScrollToMessage(mid);
                    },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l10n.beaconRoomFactCardActionCopy),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: fact.factText));
                if (rootCtx.mounted) {
                  Navigator.pop(ctx);
                  final locale = L10n.of(rootCtx)!.localeName;
                  showSnackBar(
                    rootCtx,
                    text: const BeaconFactCopiedMessage().toL10n(locale),
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.push_pin_outlined,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                l10n.beaconRoomFactCardActionRemove,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_confirmRemoveFact(rootCtx, cubit, fact, l10n));
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _confirmRemoveFact(
  BuildContext context,
  RoomCubit cubit,
  BeaconFactCard fact,
  L10n l10n,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.beaconRoomFactCardRemoveConfirmTitle),
      content: Text(l10n.beaconRoomFactCardRemoveConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.beaconRoomFactCardRemoveConfirmAction),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await cubit.removeFact(factCardId: fact.id);
  }
}

Future<void> _showEditFactSheet(
  BuildContext context,
  RoomCubit cubit,
  BeaconFactCard fact,
) async {
  final l10n = L10n.of(context)!;
  final controller = TextEditingController(text: fact.factText);
  try {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: kSpacingMedium,
            right: kSpacingMedium,
            top: kSpacingMedium,
            bottom: bottom + kSpacingMedium,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.beaconRoomFactCardEditTitle, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: kSpacingMedium),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 10,
                maxLength: 8000,
                decoration: InputDecoration(
                  hintText: l10n.beaconRoomFactCardEditHint,
                ),
              ),
              const SizedBox(height: kSpacingMedium),
              FilledButton(
                onPressed: () {
                  final t = controller.text.trim();
                  if (t.isEmpty) return;
                  Navigator.of(ctx).pop(true);
                },
                child: Text(MaterialLocalizations.of(ctx).saveButtonLabel),
              ),
            ],
          ),
        );
      },
    );
    if (ok == true && context.mounted) {
      final t = controller.text.trim();
      if (t.isEmpty) return;
      await cubit.correctFact(factCardId: fact.id, newText: t);
    }
  } finally {
    controller.dispose();
  }
}
