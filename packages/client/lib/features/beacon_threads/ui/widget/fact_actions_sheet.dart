import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/message/beacon_room_fact_messages.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_attachment_preview_strip.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_provenance_line.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/copy_text_to_clipboard.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Actions for a single fact card (modal).
Future<void> showFactActionsSheet(
  BuildContext context, {
  required RoomCubit cubit,
  required BeaconFactCard fact,
  void Function(BeaconFactCard fact)? onQuoteInChat,
}) {
  return showFactActionsHostSheet(
    context,
    fact: fact,
    canMutate: cubit.state.canWriteDiscussion,
    myUserId: cubit.state.myUserId,
    onQuoteInChat: onQuoteInChat,
    // Base seq is the one the edit sheet opened with (plan §14.6); after a
    // revision conflict, "Save mine" retries against the conflict's seq.
    onCorrect: ({
      required factCardId,
      required newText,
      String? attachmentsJson,
    }) {
      final conflict = cubit.state.factEditConflict;
      return cubit.correctFact(
        factCardId: factCardId,
        newText: newText,
        baseRevisionSeq: conflict != null && conflict.id == factCardId
            ? conflict.revisionSeq
            : fact.revisionSeq,
        attachmentsJson: attachmentsJson,
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
    String? attachmentsJson,
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
            // Every reader may browse history (baseline at seq 1 included).
            if (onEditHistory != null)
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
    String? attachmentsJson,
  })
  onCorrect, {
  bool showPinnedBy = false,
  BeaconFactCard? Function()? readEditConflict,
  VoidCallback? onClearEditConflict,
}) async {
  final l10n = L10n.of(context)!;
  var draft = fact.factText;
  var baseline = fact.factText;
  var keptAttachments = List<RoomMessageAttachment>.from(fact.attachments);
  var pending = <RoomPendingUpload>[];
  var resumedFromConflict = false;
  while (true) {
    if (!context.mounted) return;
    final result = await showTenturaAdaptiveSheet<_FactEditResult>(
      context: context,
      useRootNavigator: true,
      enableDrag: false,
      builder: (ctx) => _EditFactSheet(
        initialText: draft,
        baselineText: baseline,
        baselineAttachments: fact.attachments,
        initialKeptAttachments: keptAttachments,
        initialPending: pending,
        pinnedByLabel: showPinnedBy
            ? l10n.beaconRoomFactCardPinnedByLabel(fact.pinnedByTitle)
            : null,
        l10n: l10n,
      ),
    );
    if (result == null || !context.mounted) {
      if (resumedFromConflict) onClearEditConflict?.call();
      return;
    }
    draft = result.text;
    keptAttachments = result.keptAttachments;
    pending = result.pending;

    String? attachmentsJson;
    if (result.attachmentsChanged) {
      final repo = GetIt.I<BeaconFactCardRepository>();
      final fragments = <Map<String, Object?>>[];
      var position = 0;
      for (final a in keptAttachments) {
        fragments.add({
          'id': a.id,
          'kind': a.kind,
          'position': position++,
          'mime': a.mime,
          'sizeBytes': a.sizeBytes,
          'fileName': a.fileName,
          'imageId': a.imageId,
          'imageAuthorId': a.imageAuthorId,
          'blurHash': a.blurHash,
          'width': a.width,
          'height': a.height,
        });
      }
      for (final upload in pending) {
        final raw = await repo.uploadAttachment(
          beaconId: fact.beaconId,
          upload: upload,
        );
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          fragments.add({
            ...Map<String, Object?>.from(decoded),
            'position': position++,
          });
        }
      }
      attachmentsJson = jsonEncode(fragments);
    }

    await onCorrect(
      factCardId: fact.id,
      newText: result.text,
      attachmentsJson: attachmentsJson,
    );

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
          currentAttachments: conflict.attachments,
          myText: result.text,
          myAttachments: [
            ...keptAttachments,
            // Pending uploads are already staged into attachmentsJson when
            // present; conflict UI shows kept + a count of pending.
          ],
          myPendingCount: pending.length,
          l10n: l10n,
        ),
      );
      if (!context.mounted) return;
      switch (choice) {
        case _FactEditConflictChoice.saveMine:
          await onCorrect(
            factCardId: fact.id,
            newText: result.text,
            attachmentsJson: attachmentsJson,
          );
          continue;
        case _FactEditConflictChoice.keepEditing:
          draft = result.text;
          baseline = conflict.factText;
          keptAttachments = List<RoomMessageAttachment>.from(
            conflict.attachments,
          );
          pending = [];
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
    required this.currentAttachments,
    required this.myText,
    required this.myAttachments,
    required this.myPendingCount,
    required this.l10n,
  });

  final String currentText;
  final List<RoomMessageAttachment> currentAttachments;
  final String myText;
  final List<RoomMessageAttachment> myAttachments;
  final int myPendingCount;
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
            _ConflictAttachmentRow(attachments: currentAttachments),
            SizedBox(height: tt.sectionGap),
            TenturaMetaText(l10n.beaconRoomFactEditConflictMineLabel),
            SizedBox(height: tt.rowGap / 2),
            SelectableText(myText, style: textTheme.bodyMedium),
            _ConflictAttachmentRow(
              attachments: myAttachments,
              pendingCount: myPendingCount,
            ),
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

class _ConflictAttachmentRow extends StatelessWidget {
  const _ConflictAttachmentRow({
    required this.attachments,
    this.pendingCount = 0,
  });

  final List<RoomMessageAttachment> attachments;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final images = attachments
        .where((a) => a.isImage && a.imageId.isNotEmpty)
        .toList();
    if (images.isEmpty && pendingCount <= 0) return const SizedBox.shrink();
    final tt = context.tt;
    final thumb = tt.avatarSize;
    return Padding(
      padding: EdgeInsets.only(top: tt.tightGap),
      child: SizedBox(
        height: thumb,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: images.length + (pendingCount > 0 ? 1 : 0),
          separatorBuilder: (_, _) => SizedBox(width: tt.tightGap),
          itemBuilder: (ctx, i) {
            if (i >= images.length) {
              return SizedBox(
                width: thumb,
                height: thumb,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
                  ),
                  child: Center(
                    child: TenturaMetaText('+$pendingCount'),
                  ),
                ),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
              child: SizedBox(
                width: thumb,
                height: thumb,
                child: roomAttachmentAlbumThumbnail(ctx, images[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FactEditResult {
  const _FactEditResult({
    required this.text,
    required this.keptAttachments,
    required this.pending,
    required this.attachmentsChanged,
  });

  final String text;
  final List<RoomMessageAttachment> keptAttachments;
  final List<RoomPendingUpload> pending;
  final bool attachmentsChanged;
}

/// Keeps [TextEditingController] alive until the sheet route is torn down.
class _EditFactSheet extends StatefulWidget {
  const _EditFactSheet({
    required this.initialText,
    required this.baselineText,
    required this.baselineAttachments,
    required this.initialKeptAttachments,
    required this.initialPending,
    required this.l10n,
    this.pinnedByLabel,
  });

  final String initialText;
  final String baselineText;
  final List<RoomMessageAttachment> baselineAttachments;
  final List<RoomMessageAttachment> initialKeptAttachments;
  final List<RoomPendingUpload> initialPending;
  final String? pinnedByLabel;
  final L10n l10n;

  @override
  State<_EditFactSheet> createState() => _EditFactSheetState();
}

class _EditFactSheetState extends State<_EditFactSheet> {
  late final TextEditingController _controller;
  late List<RoomMessageAttachment> _kept;
  late List<RoomPendingUpload> _pending;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _kept = List<RoomMessageAttachment>.from(widget.initialKeptAttachments);
    _pending = List<RoomPendingUpload>.from(widget.initialPending);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _attachmentsChanged {
    if (_pending.isNotEmpty) return true;
    if (_kept.length != widget.baselineAttachments.length) return true;
    for (var i = 0; i < _kept.length; i++) {
      if (_kept[i].id != widget.baselineAttachments[i].id) return true;
    }
    return false;
  }

  bool get _isDirty =>
      _controller.text.trim() != widget.baselineText.trim() ||
      _attachmentsChanged;

  bool get _canSave {
    final text = _controller.text.trim();
    return text.isNotEmpty || _kept.isNotEmpty || _pending.isNotEmpty;
  }

  int get _remainingSlots =>
      kMaxRoomMessageAttachments - _kept.length - _pending.length;

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(
      _FactEditResult(
        text: _controller.text.trim(),
        keptAttachments: List.unmodifiable(_kept),
        pending: List.unmodifiable(_pending),
        attachmentsChanged: _attachmentsChanged,
      ),
    );
  }

  void _tryAdd(RoomPendingUpload upload) {
    if (_remainingSlots <= 0) return;
    if (upload.bytes.length > kMaxRoomMessageAttachmentBytes) return;
    setState(() => _pending.add(upload));
  }

  Future<void> _pickImages() async {
    if (_remainingSlots <= 0) return;
    final repo = GetIt.I<ImageRepository>();
    final picks = await repo.pickMultipleImages();
    if (!mounted || picks.isEmpty) return;
    for (final p in picks) {
      if (_remainingSlots <= 0) break;
      _tryAdd(
        RoomPendingUpload(
          bytes: p.bytes,
          fileName: p.fileName,
          mimeType: 'image/jpeg',
        ),
      );
    }
  }

  Future<void> _pasteImage() async {
    if (_remainingSlots <= 0) return;
    final repo = GetIt.I<ClipboardImageRepository>();
    try {
      final result = await repo.readImage();
      if (!mounted) return;
      if (result.outcome == ClipboardImageReadOutcome.found) {
        _tryAdd(result.upload!);
      }
    } on Object {
      // Ignore paste failures in the edit sheet.
    }
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
            if (_kept.isNotEmpty || _pending.isNotEmpty) ...[
              SizedBox(height: tt.rowGap),
              FactAttachmentPreviewStrip(
                existing: _kept,
                pending: [
                  for (final u in _pending)
                    (
                      bytes: u.bytes,
                      fileName: u.fileName,
                      mimeType: u.mimeType,
                    ),
                ],
                onRemoveExisting: (i) => setState(() => _kept.removeAt(i)),
                onRemovePending: (i) => setState(() => _pending.removeAt(i)),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: widget.l10n.beaconRoomAttachPasteImage,
                    icon: Icon(
                      Icons.content_paste_rounded,
                      size: tt.iconSize,
                    ),
                    onPressed: _remainingSlots > 0
                        ? () => unawaited(_pasteImage())
                        : null,
                  ),
                  IconButton(
                    tooltip: widget.l10n.beaconRoomAttachPickImages,
                    icon: Icon(Icons.add_a_photo_rounded, size: tt.iconSize),
                    onPressed: _remainingSlots > 0
                        ? () => unawaited(_pickImages())
                        : null,
                  ),
                ],
              ),
            ),
            SizedBox(height: tt.sectionGap),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: Text(MaterialLocalizations.of(context).saveButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
