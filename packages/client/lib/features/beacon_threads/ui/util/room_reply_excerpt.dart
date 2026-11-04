import 'package:tentura_root/domain/util/room_reply_excerpt.dart' as shared;

import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/ui/l10n/l10n.dart';

export 'package:tentura_root/domain/util/room_reply_excerpt.dart'
    show kRoomReplyExcerptMaxChars;

/// One-line body excerpt for a live message (null when blank). A poll has no
/// body and is quoted by its question, as the server quotes it (#377).
String? roomReplyExcerpt(RoomMessage parent) {
  if (parent.body.trim().isEmpty) {
    final question = RoomPollData.tryParse(parent.pollDataJson)?.question;
    if (question != null && question.trim().isNotEmpty) {
      return shared.roomReplyExcerptFromBody('📊 $question');
    }
  }
  return shared.roomReplyExcerptFromBody(parent.body);
}

/// Display excerpt from stored snapshot fields with attachment/unavailable fallbacks.
String roomReplyExcerptFor({
  required String? excerpt,
  required bool hasAttachments,
  required L10n l10n,
}) {
  final trimmed = excerpt?.trim() ?? '';
  if (trimmed.isNotEmpty) {
    return trimmed;
  }
  if (hasAttachments) {
    return l10n.beaconRoomReplyAttachmentExcerpt;
  }
  return l10n.beaconRoomReplyOriginalUnavailable;
}
