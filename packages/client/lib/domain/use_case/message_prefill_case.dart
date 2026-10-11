import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon/domain/port/beacon_hierarchy_repository_port.dart';

/// Request form content derived from a room message.
typedef MessagePrefill = ({String title, String description});

/// Owns how a message fills the Request form: the first line becomes the
/// title (cut to the title limit), the rest the description.
///
/// Used by budding a Request from a Post message (text only: the bud pipeline
/// takes no cover).
@singleton
class MessagePrefillCase {
  MessagePrefillCase(this._hierarchy);

  final BeaconHierarchyRepositoryPort _hierarchy;

  /// Splits [body] into title and description.
  static MessagePrefill fromText(String body) {
    final text = body.trim();
    final newline = text.indexOf('\n');
    final firstLine = (newline < 0 ? text : text.substring(0, newline)).trim();
    final rest = newline < 0 ? '' : text.substring(newline + 1).trim();
    return (
      title: firstLine.length > kBeaconTitleMaxLength
          ? firstLine.substring(0, kBeaconTitleMaxLength)
          : firstLine,
      description: rest,
    );
  }

  /// Message [sourceMessageId] of beacon [parentBeaconId], text only.
  Future<MessagePrefill> sourceMessage({
    required String parentBeaconId,
    required String sourceMessageId,
  }) async {
    final source = await _hierarchy.fetchPromotionSource(
      parentBeaconId: parentBeaconId,
      sourceMessageId: sourceMessageId,
    );
    return fromText(source.textPreview);
  }
}
