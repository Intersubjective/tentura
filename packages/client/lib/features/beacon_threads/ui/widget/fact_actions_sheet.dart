import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/message/beacon_room_fact_messages.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_provenance_line.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/copy_text_to_clipboard.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Actions for a single fact card (modal).
Future<void> showFactActionsSheet(
  BuildContext context, {
  required RoomCubit cubit,
  required BeaconFactCard fact,
}) {
  return showFactActionsHostSheet(
    context,
    fact: fact,
    canMutate: cubit.state.canWriteDiscussion,
    myUserId: cubit.state.myUserId,
    // Base seq is the one the edit sheet opened with (plan §14.6); after a
    // revision conflict, "Save mine" retries against the conflict's seq.
    onCorrect: ({required factCardId, required newText}) {
      final conflict = cubit.state.factEditConflict;
      return cubit.correctFact(
        factCardId: factCardId,
        newText: newText,
        baseRevisionSeq: conflict != null && conflict.id == factCardId
            ? conflict.revisionSeq
            : fact.revisionSeq,
      );
    },
    readEditConflict: () => cubit.state.factEditConflict,
    onClearEditConflict: cubit.clearFactEditConflict,
    onRemove: ({required factCardId}) =>
        cubit.removeFact(factCardId: factCardId),
    onSetVisibility: ({required factCardId, required visibility}) =>
        cubit.setFactVisibility(
          factCardId: factCardId,
          visibility: visibility,
        ),
    onJumpToSource: cubit.requestScrollToMessage,
    onEditHistory: (f) => unawaited(
      showFactHistorySheet(
        context,
        beaconId: cubit.state.beaconId,
        factCardId: f.id,
        baseRevisionSeq: f.revisionSeq,
        canMutate: cubit.state.canWriteDiscussion,
      ),
    ),
  );
}

Future<void> showFactActionsHostSheet(
  BuildContext context, {
  required BeaconFactCard fact,
  required Future<void> Function({
    required String factCardId,
    required String newText,
  })
  onCorrect,
  required Future<void> Function({required String factCardId}) onRemove,
  required Future<void> Function({
    required String factCardId,
    required int visibility,
  })
  onSetVisibility,
  void Function(String messageId)? onJumpToSource,
  void Function(BeaconFactCard fact)? onEditHistory,
  void Function(BeaconFactCard fact)? onQuoteInChat,
  bool canMutate = true,
  String? myUserId,
  BeaconFactCard? Function()? readEditConflict,
  VoidCallback? onClearEditConflict,
}) {
  final l10n = L10n.of(context)!;
  final pageCtx = context;

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
            Padding(
              padding: EdgeInsets.only(
                left: ctx.tt.screenHPadding,
                right: ctx.tt.screenHPadding,
                top: ctx.tt.rowGap / 2,
                bottom: ctx.tt.rowGap,
              ),
              child: FactProvenanceLine(fact: fact),
            ),
            if (canMutate) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.beaconRoomFactCardActionEdit),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(
                    _showEditFactSheet(
                      pageCtx,
                      fact,
                      onCorrect,
                      showPinnedBy:
                          myUserId != null &&
                          myUserId.isNotEmpty &&
                          fact.pinnedBy != myUserId,
                      readEditConflict: readEditConflict,
                      onClearEditConflict: onClearEditConflict,
                    ),
                  );
                },
              ),
              if (fact.visibility == BeaconFactCardVisibilityBits.room)
                ListTile(
                  leading: const Icon(Icons.public_outlined),
                  title: Text(l10n.beaconRoomFactCardActionMakePublic),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(
                      onSetVisibility(
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
                      onSetVisibility(
                        factCardId: fact.id,
                        visibility: BeaconFactCardVisibilityBits.room,
                      ),
                    );
                  },
                ),
            ],
            // Every reader may browse history once the fact has been edited.
            if (onEditHistory != null && fact.revisionSeq > 1)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(l10n.beaconRoomFactCardActionEditHistory),
                onTap: () {
                  Navigator.pop(ctx);
                  onEditHistory(fact);
                },
              ),
            if (onQuoteInChat != null)
              ListTile(
                leading: const Icon(Icons.format_quote_outlined),
                title: Text(l10n.beaconRoomFactCardActionQuoteInChat),
                onTap: () {
                  Navigator.pop(ctx);
                  onQuoteInChat(fact);
                },
              ),
            ListTile(
              leading: const Icon(Icons.message_outlined),
              title: Text(l10n.beaconRoomFactCardActionJumpToSource),
              enabled:
                  onJumpToSource != null &&
                  fact.sourceMessageId != null &&
                  fact.sourceMessageId!.isNotEmpty,
              onTap:
                  onJumpToSource == null ||
                      fact.sourceMessageId == null ||
                      fact.sourceMessageId!.isEmpty
                  ? null
                  : () {
                      final mid = fact.sourceMessageId!;
                      Navigator.pop(ctx);
                      onJumpToSource(mid);
                    },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l10n.beaconRoomFactCardActionCopy),
              onTap: () async {
                final ok = await copyTextToClipboard(fact.factText);
                if (!ok || !pageCtx.mounted) return;
                Navigator.pop(ctx);
                final locale = L10n.of(pageCtx)!.localeName;
                showSnackBar(
                  pageCtx,
                  text: const BeaconFactCopiedMessage().toL10n(locale),
                );
              },
            ),
            if (canMutate)
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
                  unawaited(_confirmRemoveFact(pageCtx, fact, l10n, onRemove));
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
  BeaconFactCard fact,
  L10n l10n,
  Future<void> Function({required String factCardId}) onRemove,
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
    await onRemove(factCardId: fact.id);
  }
}

Future<void> _showEditFactSheet(
  BuildContext context,
  BeaconFactCard fact,
  Future<void> Function({
    required String factCardId,
    required String newText,
  })
  onCorrect, {
  bool showPinnedBy = false,
  BeaconFactCard? Function()? readEditConflict,
  VoidCallback? onClearEditConflict,
}) async {
  final l10n = L10n.of(context)!;
  var draft = fact.factText;
  var baseline = fact.factText;
  var resumedFromConflict = false;
  while (true) {
    if (!context.mounted) return;
    final newText = await showTenturaAdaptiveSheet<String>(
      context: context,
      useRootNavigator: true,
      enableDrag: false,
      builder: (ctx) => _EditFactSheet(
        initialText: draft,
        baselineText: baseline,
        pinnedByLabel: showPinnedBy
            ? l10n.beaconRoomFactCardPinnedByLabel(fact.pinnedByTitle)
            : null,
        l10n: l10n,
      ),
    );
    if (newText == null || !context.mounted) {
      if (resumedFromConflict) onClearEditConflict?.call();
      return;
    }
    await onCorrect(factCardId: fact.id, newText: newText);

    // Revision conflict: loop until saved, kept theirs, or dismissed.
    while (true) {
      final conflict = readEditConflict?.call();
      if (conflict == null || conflict.id != fact.id || !context.mounted) {
        return;
      }
      final choice = await showTenturaAdaptiveSheet<_FactEditConflictChoice>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => _FactEditConflictSheet(
          currentText: conflict.factText,
          myText: newText,
          l10n: l10n,
        ),
      );
      if (!context.mounted) return;
      switch (choice) {
        case _FactEditConflictChoice.saveMine:
          await onCorrect(factCardId: fact.id, newText: newText);
          continue;
        case _FactEditConflictChoice.keepEditing:
          draft = newText;
          baseline = conflict.factText;
          resumedFromConflict = true;
        case _FactEditConflictChoice.keepTheirs:
        case null:
          onClearEditConflict?.call();
          return;
      }
      break;
    }
  }
}

enum _FactEditConflictChoice { saveMine, keepTheirs, keepEditing }

class _FactEditConflictSheet extends StatelessWidget {
  const _FactEditConflictSheet({
    required this.currentText,
    required this.myText,
    required this.l10n,
  });

  final String currentText;
  final String myText;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final textTheme = Theme.of(context).textTheme;
    void choose(_FactEditConflictChoice c) => Navigator.of(context).pop(c);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: tt.screenHPadding,
          right: tt.screenHPadding,
          top: tt.sectionGap,
          bottom: tt.sectionGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.beaconRoomFactEditConflictTitle,
              style: textTheme.titleMedium,
            ),
            SizedBox(height: tt.sectionGap),
            TenturaMetaText(l10n.beaconRoomFactEditConflictCurrentLabel),
            SizedBox(height: tt.rowGap / 2),
            SelectableText(currentText, style: textTheme.bodyMedium),
            SizedBox(height: tt.sectionGap),
            TenturaMetaText(l10n.beaconRoomFactEditConflictMineLabel),
            SizedBox(height: tt.rowGap / 2),
            SelectableText(myText, style: textTheme.bodyMedium),
            SizedBox(height: tt.sectionGap),
            FilledButton(
              onPressed: () => choose(_FactEditConflictChoice.saveMine),
              child: Text(l10n.beaconRoomFactEditConflictSaveMine),
            ),
            SizedBox(height: tt.rowGap),
            OutlinedButton(
              onPressed: () => choose(_FactEditConflictChoice.keepTheirs),
              child: Text(l10n.beaconRoomFactEditConflictKeepTheirs),
            ),
            SizedBox(height: tt.rowGap),
            TextButton(
              onPressed: () => choose(_FactEditConflictChoice.keepEditing),
              child: Text(l10n.beaconRoomFactEditConflictKeepEditing),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps [TextEditingController] alive until the sheet route is torn down.
class _EditFactSheet extends StatefulWidget {
  const _EditFactSheet({
    required this.initialText,
    required this.baselineText,
    required this.l10n,
    this.pinnedByLabel,
  });

  final String initialText;

  /// Text the dirty guard compares against (server text).
  final String baselineText;

  /// "Pinned by …" banner, shown when the editor is not the pinner.
  final String? pinnedByLabel;
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

  bool get _isDirty => _controller.text.trim() != widget.baselineText.trim();

  void _save() {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return TenturaSheetDismissGuard(
      isDirty: _isDirty,
      useRootNavigator: true,
      child: Padding(
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
            if (widget.pinnedByLabel case final label?) ...[
              SizedBox(height: tt.rowGap),
              Row(
                children: [
                  Icon(
                    Icons.push_pin_outlined,
                    size: tt.iconSize,
                    color: tt.textMuted,
                  ),
                  SizedBox(width: tt.rowGap / 2),
                  Expanded(child: TenturaMetaText(label, maxLines: 2)),
                ],
              ),
            ],
            SizedBox(height: tt.sectionGap),
            TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 10,
              maxLength: 8000,
              decoration: InputDecoration(
                hintText: widget.l10n.beaconRoomFactCardEditHint,
              ),
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: tt.sectionGap),
            FilledButton(
              onPressed: _save,
              child: Text(MaterialLocalizations.of(context).saveButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
