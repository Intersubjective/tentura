import 'package:tentura/domain/entity/coordination_item.dart';

/// Deterministic v1: match draft text against open item titles (word overlap).
CoordinationItem? suggestPromote({
  required String draftText,
  required List<CoordinationItem> openItems,
  String? replyToMessageId,
}) {
  final draft = draftText.trim().toLowerCase();
  if (draft.length < 8 || openItems.isEmpty) return null;

  CoordinationItem? best;
  var bestScore = 0;

  for (final item in openItems) {
    if (!item.isActive) continue;
    final title = item.title.trim().toLowerCase();
    if (title.length < 4) continue;

    var score = 0;
    if (draft.contains(title)) {
      score = title.length + 10;
    } else {
      for (final word in title.split(RegExp(r'\s+'))) {
        if (word.length >= 4 && draft.contains(word)) {
          score += word.length;
        }
      }
    }
    if (score > bestScore) {
      bestScore = score;
      best = item;
    }
  }

  return bestScore >= 6 ? best : null;
}
