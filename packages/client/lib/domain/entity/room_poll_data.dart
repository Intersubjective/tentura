import 'dart:convert';

enum PollType { single, multiple, range }

class RoomPollVariant {
  const RoomPollVariant({
    required this.id,
    required this.description,
    required this.votesCount,
    this.avgScore,
    this.voterIds,
  });

  final String id;
  final String description;
  final int votesCount;

  /// Average score (range polls only).
  final double? avgScore;

  /// Voter user IDs (open polls, visible only after the viewer has voted).
  final List<String>? voterIds;

  static RoomPollVariant fromJson(Map<String, dynamic> j) => RoomPollVariant(
    id: j['id'] as String,
    description: j['description'] as String,
    votesCount: (j['votesCount'] as num).toInt(),
    avgScore: (j['avgScore'] as num?)?.toDouble(),
    voterIds: (j['voterIds'] as List?)?.cast<String>(),
  );
}

class RoomPollData {
  const RoomPollData({
    required this.id,
    required this.question,
    required this.variants,
    required this.totalVotes,
    required this.myVariantIds,
    this.pollType = PollType.single,
    this.isAnonymous = true,
    this.allowRevote = true,
  });

  final String id;
  final String question;
  final PollType pollType;
  final bool isAnonymous;
  final bool allowRevote;
  final List<String> myVariantIds;
  final int totalVotes;
  final List<RoomPollVariant> variants;

  bool get hasVoted => myVariantIds.isNotEmpty;

  bool isMyVote(String variantId) => myVariantIds.contains(variantId);

  double percentageFor(String variantId) {
    if (totalVotes == 0) return 0;
    final v = variants.where((e) => e.id == variantId).firstOrNull;
    if (v == null) return 0;
    return v.votesCount / totalVotes;
  }

  RoomPollData withOptimisticVote({
    required List<String> variantIds,
    int? score,
  }) {
    final wasVoted = hasVoted;
    final previousIds = myVariantIds.toSet();
    final newIds = variantIds.toSet();

    List<RoomPollVariant> updatedVariants;
    int updatedTotal = totalVotes;

    switch (pollType) {
      case PollType.single:
        final prevId = previousIds.firstOrNull;
        updatedTotal = wasVoted ? totalVotes : totalVotes + 1;
        updatedVariants = [
          for (final v in variants)
            if (v.id == variantIds.first)
              RoomPollVariant(
                id: v.id,
                description: v.description,
                votesCount: v.votesCount + (prevId == v.id ? 0 : 1),
                avgScore: v.avgScore,
                voterIds: v.voterIds,
              )
            else if (v.id == prevId)
              RoomPollVariant(
                id: v.id,
                description: v.description,
                votesCount: (v.votesCount - 1).clamp(0, v.votesCount),
                avgScore: v.avgScore,
                voterIds: v.voterIds,
              )
            else
              v,
        ];

      case PollType.multiple:
        // variantIds contains the toggled variant
        final toggledId = variantIds.first;
        final removing = previousIds.contains(toggledId);
        final newMyIds = removing
            ? (previousIds..remove(toggledId)).toList()
            : [...previousIds, toggledId];
        if (!wasVoted && !removing) updatedTotal = totalVotes + 1;
        if (wasVoted && removing && newMyIds.isEmpty) {
          updatedTotal = (totalVotes - 1).clamp(0, totalVotes);
        }
        updatedVariants = [
          for (final v in variants)
            if (v.id == toggledId)
              RoomPollVariant(
                id: v.id,
                description: v.description,
                votesCount:
                    removing ? (v.votesCount - 1).clamp(0, v.votesCount) : v.votesCount + 1,
                avgScore: v.avgScore,
                voterIds: v.voterIds,
              )
            else
              v,
        ];
        return RoomPollData(
          id: id,
          question: question,
          pollType: pollType,
          isAnonymous: isAnonymous,
          allowRevote: allowRevote,
          myVariantIds: newMyIds,
          totalVotes: updatedTotal,
          variants: updatedVariants,
        );

      case PollType.range:
        updatedTotal = wasVoted ? totalVotes : totalVotes + 1;
        // Approximate avgScore optimistically
        updatedVariants = [
          for (final v in variants)
            if (newIds.contains(v.id) && score != null)
              RoomPollVariant(
                id: v.id,
                description: v.description,
                votesCount: previousIds.contains(v.id) ? v.votesCount : v.votesCount + 1,
                avgScore: score.toDouble(),
                voterIds: v.voterIds,
              )
            else
              v,
        ];
    }

    return RoomPollData(
      id: id,
      question: question,
      pollType: pollType,
      isAnonymous: isAnonymous,
      allowRevote: allowRevote,
      myVariantIds: variantIds,
      totalVotes: updatedTotal,
      variants: updatedVariants,
    );
  }

  String encode() => jsonEncode({
    'id': id,
    'question': question,
    'pollType': pollType.name,
    'isAnonymous': isAnonymous,
    'allowRevote': allowRevote,
    'myVariantIds': myVariantIds,
    'totalVotes': totalVotes,
    'variants': [
      for (final v in variants)
        {
          'id': v.id,
          'description': v.description,
          'votesCount': v.votesCount,
          if (v.avgScore != null) 'avgScore': v.avgScore,
          if (v.voterIds != null) 'voterIds': v.voterIds,
        },
    ],
  });

  static PollType _parsePollType(dynamic raw) => switch (raw) {
    'multiple' => PollType.multiple,
    'range' => PollType.range,
    _ => PollType.single,
  };

  static RoomPollData? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      final variantList = map['variants'];
      if (variantList is! List) return null;
      return RoomPollData(
        id: map['id'] as String,
        question: map['question'] as String,
        pollType: _parsePollType(map['pollType']),
        isAnonymous: map['isAnonymous'] as bool? ?? true,
        allowRevote: map['allowRevote'] as bool? ?? true,
        totalVotes: (map['totalVotes'] as num).toInt(),
        myVariantIds: (map['myVariantIds'] as List?)?.cast<String>() ?? [],
        variants: variantList
            .cast<Map<String, dynamic>>()
            .map(RoomPollVariant.fromJson)
            .toList(),
      );
    } on Object catch (_) {
      return null;
    }
  }
}
