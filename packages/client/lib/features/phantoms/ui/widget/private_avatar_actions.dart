import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/ui_utils.dart';

import '../../data/repository/private_avatar_repository.dart';
import '../../domain/entity/person_note.dart';

class PrivateAvatarActions extends StatefulWidget {
  const PrivateAvatarActions({
    required this.subject,
    required this.hasPhoto,
    required this.onChanged,
    super.key,
  });

  final PersonNoteSubject subject;
  final bool hasPhoto;
  final Future<void> Function() onChanged;

  @override
  State<PrivateAvatarActions> createState() => _PrivateAvatarActionsState();
}

class _PrivateAvatarActionsState extends State<PrivateAvatarActions> {
  static const _avatars = PrivateAvatarRepository();

  bool _busy = false;

  Future<void> _change({required bool remove}) async {
    if (_busy) return;
    final subject = widget.subject;
    final onChanged = widget.onChanged;
    setState(() => _busy = true);
    try {
      if (remove) {
        await _avatars.remove(subject);
      } else {
        final photo = await GetIt.I<ImageRepository>().pickImage();
        if (photo == null || !mounted) return;
        await _avatars.upload(subject, photo);
      }
      await onChanged();
    } on Exception catch (error, trace) {
      if (mounted) {
        showSnackBar(
          context,
          text: L10n.of(context)!.errorGenericAction,
          isError: true,
          error: error,
          stackTrace: trace,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: widget.hasPhoto
              ? l10n.personPhotoChange
              : l10n.personPhotoAdd,
          onPressed: _busy ? null : () => _change(remove: false),
          icon: Icon(
            widget.hasPhoto ? Icons.image_outlined : Icons.add_a_photo_outlined,
          ),
        ),
        if (widget.hasPhoto)
          IconButton(
            tooltip: l10n.personPhotoRemove,
            onPressed: _busy ? null : () => _change(remove: true),
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    );
  }
}
