import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:share_plus/share_plus.dart';

import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Future<void> openRoomFileAttachment(
  BuildContext context,
  L10n l10n,
  RoomMessageAttachment attachment,
) async {
  try {
    final bytes = await GetIt.I<BeaconRoomCase>().downloadRoomAttachment(
      attachment.id,
    );
    final name = attachment.fileName.trim().isEmpty
        ? 'file'
        : attachment.fileName.trim();
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: name,
            mimeType: attachment.mime,
          ),
        ],
      ),
    );
  } on Object catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.beaconRoomAttachmentOpenFailed)),
      );
    }
  }
}
