import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/utils/infer_image_mime_from_bytes.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/features/beacon_view/domain/pinned_facts.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

Future<void> showBeaconFactComposerSheet(
  BuildContext pageContext, {
  required BeaconViewCubit cubit,
  ImageRepository? imageRepository,
  ClipboardImageRepository? clipboardImageRepository,
}) {
  return showTenturaAdaptiveSheet<void>(
    context: pageContext,
    builder: (ctx) => _BeaconFactComposerBody(
      cubit: cubit,
      imageRepository: imageRepository,
      clipboardImageRepository: clipboardImageRepository,
    ),
  );
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
  State<_BeaconFactComposerBody> createState() => _BeaconFactComposerBodyState();
}

class _BeaconFactComposerBodyState extends State<_BeaconFactComposerBody> {
  final _text = TextEditingController();
  final _pending = <RoomPendingUpload>[];
  var _visibility = BeaconFactCardVisibilityBits.public;
  var _submitting = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _remainingSlots => kMaxRoomMessageAttachments - _pending.length;

  bool get _canSubmit =>
      !_submitting &&
      (_text.text.trim().isNotEmpty || _pending.isNotEmpty);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _withinSize(List<int> bytes) {
    if (bytes.length <= kMaxRoomMessageAttachmentBytes) return true;
    const mb = kMaxRoomMessageAttachmentBytes ~/ (1024 * 1024);
    _snack(L10n.of(context)!.beaconRoomAttachmentTooLarge(mb));
    return false;
  }

  void _tryAdd(RoomPendingUpload upload) {
    if (_remainingSlots <= 0) {
      _snack(
        L10n.of(context)!.beaconRoomAttachmentsTooMany(
          kMaxRoomMessageAttachments,
        ),
      );
      return;
    }
    if (!_withinSize(upload.bytes)) return;
    setState(() => _pending.add(upload));
  }

  String _mimeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  String? _extensionFromFileName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1).trim();
  }

  Future<void> _pickImages() async {
    if (_remainingSlots <= 0) {
      _snack(
        L10n.of(context)!.beaconRoomAttachmentsTooMany(
          kMaxRoomMessageAttachments,
        ),
      );
      return;
    }
    final repo = widget.imageRepository ?? GetIt.I<ImageRepository>();
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
    if (_remainingSlots <= 0) {
      _snack(
        L10n.of(context)!.beaconRoomAttachmentsTooMany(
          kMaxRoomMessageAttachments,
        ),
      );
      return;
    }
    final l10n = L10n.of(context)!;
    final repo =
        widget.clipboardImageRepository ?? GetIt.I<ClipboardImageRepository>();
    try {
      final result = await repo.readImage();
      if (!mounted) return;
      switch (result.outcome) {
        case ClipboardImageReadOutcome.found:
          _tryAdd(result.upload!);
        case ClipboardImageReadOutcome.notFound:
          _snack(l10n.beaconRoomAttachPasteImageNotFound);
        case ClipboardImageReadOutcome.unsupported:
          _snack(l10n.beaconRoomAttachPasteImageUnsupported);
      }
    } on Object catch (_) {
      if (!mounted) return;
      _snack(l10n.beaconRoomAttachPasteImageReadFailed);
    }
  }

  Future<void> _pickFiles() async {
    if (_remainingSlots <= 0) {
      _snack(
        L10n.of(context)!.beaconRoomAttachmentsTooMany(
          kMaxRoomMessageAttachments,
        ),
      );
      return;
    }
    final files = await FilePicker.pickFiles();
    if (!mounted || files.isEmpty) return;
    for (final pf in files) {
      if (_remainingSlots <= 0) break;
      final bytes = await pf.readAsBytes();
      final ext = _extensionFromFileName(pf.name);
      var mime = ext != null && ext.isNotEmpty
          ? _mimeFromExtension(ext)
          : 'application/octet-stream';
      final sniffed = inferImageMimeFromLeadingBytes(bytes);
      if (sniffed != null) mime = sniffed;
      _tryAdd(
        RoomPendingUpload(
          bytes: bytes,
          fileName: pf.name,
          mimeType: mime,
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final l10n = L10n.of(context)!;
    final rawText = _text.text;
    final uploads = List<RoomPendingUpload>.from(_pending);
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
      Navigator.of(context).pop();
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
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.beaconRoomFactCardEditHint,
              ),
            ),
            if (_pending.isNotEmpty) ...[
              SizedBox(height: tt.rowGap),
              for (var i = 0; i < _pending.length; i++)
                ListTile(
                  dense: true,
                  title: Text(
                    _pending[i].fileName,
                    style: TenturaText.bodyMedium(
                      Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.close, size: tt.iconSize),
                    tooltip: l10n.buttonRemove,
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _pending.removeAt(i)),
                  ),
                ),
            ],
            SizedBox(height: tt.rowGap),
            Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                tooltip: l10n.beaconRoomAttachMenuTooltip,
                enabled: !_submitting && _remainingSlots > 0,
                icon: Icon(Icons.attach_file_rounded, size: tt.iconSize),
                onSelected: (v) async {
                  if (_submitting) return;
                  if (v == 'img') {
                    await _pickImages();
                  } else if (v == 'file') {
                    await _pickFiles();
                  } else if (v == 'paste') {
                    await _pasteImage();
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
                  PopupMenuItem(
                    value: 'paste',
                    child: Text(l10n.beaconRoomAttachPasteImage),
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
                  onPressed: _canSubmit ? () => unawaited(_submit()) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
