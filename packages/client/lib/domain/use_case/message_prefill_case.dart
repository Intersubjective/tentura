import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/port/post_conversion_port.dart';
import 'package:tentura/features/beacon/domain/port/beacon_hierarchy_repository_port.dart';

/// Request form content derived from a room message.
typedef MessagePrefill = ({
  String title,
  String description,
  ImageEntity? coverSuggestion,
});

/// Owns how a message fills the Request form: the first line becomes the
/// title (cut to the title limit), the rest the description.
///
/// Used by the Post conversion flow (the Post's root message, with its first
/// image as a cover suggestion) and by budding a Request from a Post message
/// (no cover: the bud pipeline takes none).
@singleton
class MessagePrefillCase {
  MessagePrefillCase(this._conversion, this._hierarchy);

  final PostConversionPort _conversion;

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
      coverSuggestion: null,
    );
  }

  /// The Post's root message, with its first image as a cover suggestion.
  Future<MessagePrefill> postRoot(String postId) async {
    final root = await _conversion.fetchRootContent(postId);
    final split = fromText(root.body);
    return (
      title: split.title,
      description: split.description,
      coverSuggestion: root.firstImage,
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
