import 'package:tentura/domain/entity/coordination_item.dart';

/// Stub: activated in PR5.
/// Returns the matching [CoordinationItem] if the draft text suggests the user
/// is discussing an open item, or `null` if no match.
CoordinationItem? suggestPromote({
  required String draftText,
  required List<CoordinationItem> openItems,
  String? replyToMessageId,
}) {
  return null;
}
