import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
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

  return showTenturaAdaptiveSheet<void>(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: ctx.tt.screenHPadding,
                right: ctx.tt.screenHPadding,
                top: ctx.tt.rowGap,
              ),
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
              enabled:
                  fact.sourceMessageId != null &&
                  fact.sourceMessageId!.isNotEmpty,
              onTap:
                  fact.sourceMessageId == null || fact.sourceMessageId!.isEmpty
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
    useRootNavigator: true,
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
  final newText = await showTenturaAdaptiveSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useRootNavigator: true,
    enableDrag: false,
    builder: (ctx) => _EditFactSheet(
      initialText: fact.factText,
      l10n: l10n,
    ),
  );
  if (newText == null || !context.mounted) return;
  await cubit.correctFact(factCardId: fact.id, newText: newText);
}

/// Keeps [TextEditingController] alive until the sheet route is torn down.
class _EditFactSheet extends StatefulWidget {
  const _EditFactSheet({
    required this.initialText,
    required this.l10n,
  });

  final String initialText;
  final L10n l10n;

  @override
  State<_EditFactSheet> createState() => _EditFactSheetState();
}

class _EditFactSheetState extends State<_EditFactSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: tt.screenHPadding,
        right: tt.screenHPadding,
        top: tt.sectionGap,
        bottom: bottom + tt.sectionGap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.l10n.beaconRoomFactCardEditTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tt.sectionGap),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 10,
            maxLength: 8000,
            decoration: InputDecoration(
              hintText: widget.l10n.beaconRoomFactCardEditHint,
            ),
          ),
          SizedBox(height: tt.sectionGap),
          FilledButton(
            onPressed: _save,
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
          ),
        ],
      ),
    );
  }
}
