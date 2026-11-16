import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'room_file_save.dart';

Future<void> openRoomFileAttachment(
  BuildContext context,
  L10n l10n,
  RoomMessageAttachment attachment,
) async {
  try {
    final bytes = await GetIt.I<BeaconThreadsCase>().downloadRoomAttachment(
      attachment.id,
    );
    final name = attachment.fileName.trim().isEmpty
        ? 'file'
        : attachment.fileName.trim();
    await saveRoomFile(bytes, name, attachment.mime);
  } on Object catch (e, st) {
    GetIt.I<Logger>().severe('Open room attachment ${attachment.id}', e, st);
    if (context.mounted) {
      showSnackBar(context, text: l10n.beaconRoomAttachmentOpenFailed);
    }
  }
}
