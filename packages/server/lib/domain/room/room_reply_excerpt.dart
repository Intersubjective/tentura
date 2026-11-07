import 'package:tentura_root/domain/util/room_reply_excerpt.dart' as shared;

export 'package:tentura_root/domain/util/room_reply_excerpt.dart'
    show kRoomReplyExcerptMaxChars;

/// One-line excerpt of a quoted message body, using the shared rune limit.
///
/// A poll message has no body: pass its [pollQuestion] and the excerpt is
/// `📊 <question>` (#377).
String? roomReplyExcerpt(String? body, {String? pollQuestion}) {
  final question = pollQuestion?.trim() ?? '';
  final text = (body ?? '').trim().isEmpty && question.isNotEmpty
      ? '📊 $question'
      : body;
  return shared.roomReplyExcerptFromBody(text);
}
