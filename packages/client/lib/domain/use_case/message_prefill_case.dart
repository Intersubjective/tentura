import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon/domain/port/beacon_hierarchy_repository_port.dart';

/// Request form content derived from a room message.
typedef MessagePrefill = ({String title, String description});

/// Owns how a message fills the Request form: the first line becomes the
/// title, the rest the description. A first line over the title limit is
/// cut at a word boundary with "…", and the whole text goes into the
/// description so nothing is lost (#729).
///
/// Used by budding a Request from a Post message (text only: the bud pipeline
/// takes no cover) and by a child Request from a room message (#735).
@singleton
class MessagePrefillCase {
  MessagePrefillCase(this._hierarchy);

  final BeaconHierarchyRepositoryPort _hierarchy;

  static const _ellipsis = '…';

  /// Splits [body] into title and description.
  static MessagePrefill fromText(String body) {
    final text = body.trim();
    final newline = text.indexOf('\n');
    final firstLine = (newline < 0 ? text : text.substring(0, newline)).trim();
    if (firstLine.length > kBeaconTitleMaxLength) {
      return (
        title: _shortTitle(firstLine, kBeaconTitleMaxLength),
        description: text,
      );
    }
    final rest = newline < 0 ? '' : text.substring(newline + 1).trim();
    return (title: firstLine, description: rest);
  }

  /// [line] shortened to at most [max] code units ending in "…": cut at the
  /// last word boundary that fits, or mid-word when the first word alone is
  /// too long. That mid-word fallback keeps surrogate pairs whole but is not
  /// grapheme-aware, so it can still split a ZWJ emoji sequence or a base
  /// letter from its combining mark (rare: one very long first word).
  static String _shortTitle(String line, int max) {
    final room = max - _ellipsis.length;
    var head = _cutCodeUnits(line, room);
    final space = head.lastIndexOf(RegExp(r'\s'));
    // A space right at the cut means the cut is already at a word end.
    final atWordEnd = RegExp(r'\s').hasMatch(line[head.length]);
    if (!atWordEnd && space > 0) head = head.substring(0, space);
    // No dangling separator before the ellipsis ("cleanup —…").
    head = head.replaceFirst(RegExp(r'[\s\-–—,;:]+$'), '');
    if (head.isEmpty) head = _cutCodeUnits(line, room);
    return '$head$_ellipsis';
  }

  /// [s] cut to at most [max] UTF-16 code units (the unit the server checks),
  /// never between the two halves of a surrogate pair.
  static String _cutCodeUnits(String s, int max) {
    if (s.length <= max) return s;
    var end = max;
    final last = s.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return s.substring(0, end);
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
