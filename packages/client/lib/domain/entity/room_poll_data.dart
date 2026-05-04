import 'dart:convert';

class RoomPollVariant {
  const RoomPollVariant({
    required this.id,
    required this.description,
    required this.votesCount,
  });

  final String id;
  final String description;
  final int votesCount;

  static RoomPollVariant fromJson(Map<String, dynamic> j) => RoomPollVariant(
    id: j['id'] as String,
    description: j['description'] as String,
    votesCount: (j['votesCount'] as num).toInt(),
  );
}

class RoomPollData {
  const RoomPollData({
    required this.id,
    required this.question,
    required this.variants,
    required this.totalVotes,
    this.myVariantId,
  });

  final String id;
  final String question;
  final List<RoomPollVariant> variants;
  final int totalVotes;
  final String? myVariantId;

  bool get hasVoted => myVariantId != null;

  double percentageFor(String variantId) {
    if (totalVotes == 0) return 0;
    final v = variants.where((e) => e.id == variantId).firstOrNull;
    if (v == null) return 0;
    return v.votesCount / totalVotes;
  }

  RoomPollData withOptimisticVote(String variantId) => RoomPollData(
    id: id,
    question: question,
    totalVotes: totalVotes + 1,
    myVariantId: variantId,
    variants: [
      for (final v in variants)
        if (v.id == variantId)
          RoomPollVariant(
            id: v.id,
            description: v.description,
            votesCount: v.votesCount + 1,
          )
        else
          v,
    ],
  );

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
        totalVotes: (map['totalVotes'] as num).toInt(),
        myVariantId: map['myVariantId'] as String?,
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
