import 'package:tentura/domain/entity/profile.dart';

enum LineageSuggestionGroup {
  involved,
  reviewedPositive,
  routedHelp,
  privateTag,
}

extension LineageSuggestionGroupWire on LineageSuggestionGroup {
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
    this.reasonArg,
    required this.autoSelect,
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

class LineagePreviewRow {
  const LineagePreviewRow({
    required this.profile,
    required this.group,
    required this.reasonCode,
    this.reasonArg,
  });

  final Profile profile;
  final LineageSuggestionGroup group;
  final String reasonCode;
  final String? reasonArg;
}
