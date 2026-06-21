/// Raw facts from lineage memory reads (no policy).
class LineageForwardEdgeFact {
  const LineageForwardEdgeFact({
    required this.recipientId,
    required this.note,
    required this.createdAt,
    required this.beaconId,
    required this.rejected,
  });

  final String recipientId;
  final String note;
  final DateTime createdAt;
  final String beaconId;
  final bool rejected;
}

class LineageEvaluationFact {
  const LineageEvaluationFact({
    required this.evaluatedUserId,
    required this.value,
    required this.reasonTags,
  });

  final String evaluatedUserId;
  final int value;
  final String reasonTags;
}

class LineagePrivateTagFact {
  const LineagePrivateTagFact({
    required this.subjectUserId,
    required this.slug,
  });

  final String subjectUserId;
  final String slug;
}

enum LineageSuggestionGroup {
  involved,
  reviewedPositive,
  routedHelp,
  privateTag,
}

extension LineageSuggestionGroupWire on LineageSuggestionGroup {
  String get wireSlug => switch (this) {
        LineageSuggestionGroup.involved => 'involved',
        LineageSuggestionGroup.reviewedPositive => 'reviewedPositive',
        LineageSuggestionGroup.routedHelp => 'routedHelp',
        LineageSuggestionGroup.privateTag => 'privateTag',
      };

  static LineageSuggestionGroup? fromWire(String slug) => switch (slug) {
        'involved' => LineageSuggestionGroup.involved,
        'reviewedPositive' => LineageSuggestionGroup.reviewedPositive,
        'routedHelp' => LineageSuggestionGroup.routedHelp,
        'privateTag' => LineageSuggestionGroup.privateTag,
        _ => null,
      };
}

class LineageForwardSuggestion {
  const LineageForwardSuggestion({
    required this.userId,
    required this.group,
    required this.reasonCode,
    required this.autoSelect, this.reasonArg,
  });

  final String userId;
  final LineageSuggestionGroup group;
  final String reasonCode;
  final String? reasonArg;
  final bool autoSelect;
}

class LineageForwardSuggestions {
  const LineageForwardSuggestions({
    required this.sourceBeaconId,
    required this.rootBeaconId,
    required this.suggestedNote,
    required this.suggestions,
  });

  final String sourceBeaconId;
  final String rootBeaconId;
  final String suggestedNote;
  final List<LineageForwardSuggestion> suggestions;
}

/// Stable reason slugs emitted to the client (mapped to l10n there).
abstract final class LineageSuggestionReasonCodes {
  static const helpedBefore = 'lineageReasonHelpedBefore';
  static const reviewedHelpful = 'lineageReasonReviewedHelpful';
  static const routedHelp = 'lineageReasonRoutedHelp';
  static const privateTag = 'lineageReasonPrivateTag';
}
