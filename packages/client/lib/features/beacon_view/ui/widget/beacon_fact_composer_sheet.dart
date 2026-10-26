import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_attachment_preview_strip.dart';
import 'package:tentura/features/beacon_view/domain/pinned_facts.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/pending_attachments.dart';

/// Opens the Add-fact form; completes with true when a fact was pinned, false
/// when the form was cancelled or dismissed (#481).
Future<bool> showBeaconFactComposerSheet(
  BuildContext pageContext, {
  required BeaconViewCubit cubit,
  ImageRepository? imageRepository,
  ClipboardImageRepository? clipboardImageRepository,
}) async {
  final saved = await showTenturaAdaptiveSheet<bool>(
    context: pageContext,
    builder: (ctx) => _BeaconFactComposerBody(
      cubit: cubit,
      imageRepository: imageRepository,
      clipboardImageRepository: clipboardImageRepository,
    ),
  );
  // A posted-but-unpinned message belongs to this form only (#759).
  cubit.forgetUnpinnedFactPost();
  return saved ?? false;
}

class _BeaconFactComposerBody extends StatefulWidget {
  const _BeaconFactComposerBody({
    required this.cubit,
    this.imageRepository,
    this.clipboardImageRepository,
  });

  final BeaconViewCubit cubit;
  final ImageRepository? imageRepository;
  final ClipboardImageRepository? clipboardImageRepository;

  @override
  State<_BeaconFactComposerBody> createState() =>
      _BeaconFactComposerBodyState();
}

class _BeaconFactComposerBodyState extends State<_BeaconFactComposerBody>
    with PendingAttachmentsMixin {
  final _text = TextEditingController();
  var _visibility = BeaconFactCardVisibilityBits.public;
  var _submitting = false;

  /// Set when Pin is tapped with nothing to pin; cleared on typing (#481).
  var _showEmptyError = false;

  @override
  ImageRepository get attachmentImageRepository =>
      widget.imageRepository ?? GetIt.I<ImageRepository>();

  @override
  ClipboardImageRepository get attachmentClipboardRepository =>
      widget.clipboardImageRepository ?? GetIt.I<ClipboardImageRepository>();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _hasContent =>
      _text.text.trim().isNotEmpty || pendingUploads.isNotEmpty;

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_hasContent) {
      // #481: say what is missing instead of a silently dead Pin.
      setState(() => _showEmptyError = true);
      return;
    }
    final l10n = L10n.of(context)!;
    final rawText = _text.text;
    final uploads = List<RoomPendingUpload>.from(pendingUploads);
    final factText = pinFactTextForPin(
      body: rawText,
      attachmentCount: uploads.length,
      attachmentFileNames: [
        for (final u in uploads)
          if (u.fileName.trim().isNotEmpty) u.fileName.trim(),
      ],
      attachmentFallback: l10n.beaconRoomPinFactAttachmentBodyFallback,
    );
    if (factText.isEmpty) return;
    setState(() => _submitting = true);
    final ok = await widget.cubit.pinFactFromComposer(
      messageBody: rawText,
      factText: factText,
      visibility: _visibility,
      uploads: uploads,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final material = MaterialLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tt.screenHPadding,
          tt.tightGap * 2,
          tt.screenHPadding,
          tt.rowGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.beaconFactsComposerTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            SizedBox(height: tt.tightGap),
            Text(
              l10n.beaconFactsComposerPostsToDiscussion,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
            SizedBox(height: tt.rowGap),
            TextField(
              controller: _text,
              enabled: !_submitting,
              minLines: 2,
              maxLines: 6,
              onChanged: (_) => setState(() => _showEmptyError = false),
              decoration: InputDecoration(
                hintText: l10n.beaconRoomFactCardEditHint,
                errorText: _showEmptyError && !_hasContent
                    ? l10n.beaconFactsComposerEmptyError
                    : null,
              ),
            ),
            if (pendingUploads.isNotEmpty) ...[
              SizedBox(height: tt.rowGap),
              FactAttachmentPreviewStrip(
                existing: const [],
                pending: [
                  for (final u in pendingUploads)
                    (
                      bytes: u.bytes,
                      fileName: u.fileName,
                      mimeType: u.mimeType,
                    ),
                ],
                onRemoveExisting: (_) {},
                onRemovePending: (i) {
                  if (_submitting) return;
                  removePendingUpload(i);
                },
                enabled: !_submitting,
              ),
            ],
            SizedBox(height: tt.rowGap),
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('paste'),
                    tooltip: l10n.beaconRoomAttachPasteImage,
                    icon: Icon(
                      Icons.content_paste_rounded,
                      size: tt.iconSize,
                    ),
                    onPressed: !_submitting && remainingAttachmentSlots > 0
                        ? () => unawaited(pasteImageAttachment())
                        : null,
                  ),
                  PopupMenuButton<String>(
                    tooltip: l10n.beaconRoomAttachMenuTooltip,
                    enabled: !_submitting && remainingAttachmentSlots > 0,
                    icon: Icon(Icons.attach_file_rounded, size: tt.iconSize),
                    onSelected: (v) async {
                      if (_submitting) return;
                      if (v == 'img') {
                        await pickImageAttachments();
                      } else if (v == 'file') {
                        await pickFileAttachments();
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'img',
                        child: Text(l10n.beaconRoomAttachPickImages),
                      ),
                      PopupMenuItem(
                        value: 'file',
                        child: Text(l10n.beaconRoomAttachPickFiles),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            RadioGroup<int>(
              groupValue: _visibility,
              onChanged: (v) {
                if (_submitting || v == null) return;
                setState(() => _visibility = v);
              },
              child: Column(
                children: [
                  RadioListTile<int>(
                    title: Text(l10n.beaconRoomPinFactPublic),
                    value: BeaconFactCardVisibilityBits.public,
                  ),
                  RadioListTile<int>(
                    title: Text(l10n.beaconRoomPinFactRoomOnly),
                    value: BeaconFactCardVisibilityBits.room,
                  ),
                ],
              ),
            ),
            SizedBox(height: tt.rowGap),
            Row(
              children: [
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(material.cancelButtonLabel),
                ),
                const Spacer(),
                TenturaCommandButton(
                  key: TestIds.key(TestIds.beaconFactsComposerSubmit),
                  label: l10n.beaconFactsComposerPin,
                  onPressed: _submitting ? null : () => unawaited(_submit()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
