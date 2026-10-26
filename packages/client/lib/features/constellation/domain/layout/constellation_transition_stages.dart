/// When one person takes part in a bulk layout transition.
typedef ConstellationTransitionStage = ({Duration delay, Duration duration});

/// Longest a whole staged transition runs.
const kConstellationTransitionDuration = Duration(milliseconds: 500);

/// Most distinct stages one transition is split into.
const kConstellationTransitionMaxStages = 8;

/// Staggers a bulk move by community: everyone in one community shares one
/// stage, and the communities (in id order) are grouped into at most
/// [maxStages] stages that start one after another and together end exactly at
/// [totalDuration]. Many people move as a few staged groups, not as one
/// independent tween each. Reduced motion lands everyone at once.
Map<String, ConstellationTransitionStage> stageConstellationTransition({
  required Map<String, Set<String>> communities,
  Duration totalDuration = kConstellationTransitionDuration,
  int maxStages = kConstellationTransitionMaxStages,
  bool reducedMotion = false,
}) {
  if (reducedMotion) {
    return {
      for (final members in communities.values)
        for (final id in members)
          id: (delay: Duration.zero, duration: Duration.zero),
    };
  }
  final ids = communities.keys.toList()..sort();
  final stageCount = ids.length < maxStages ? ids.length : maxStages;
  final totalUs = totalDuration.inMicroseconds;
  // With several stages each runs half the total; the last one lands on it.
  final durationUs = stageCount > 1 ? totalUs ~/ 2 : totalUs;
  final stages = <String, ConstellationTransitionStage>{};
  for (var i = 0; i < ids.length; i++) {
    final stage = i * stageCount ~/ ids.length;
    final delayUs = stageCount > 1
        ? (totalUs - durationUs) * stage ~/ (stageCount - 1)
        : 0;
    final value = (
      delay: Duration(microseconds: delayUs),
      duration: Duration(microseconds: durationUs),
    );
    for (final id in communities[ids[i]]!) {
      stages[id] = value;
    }
  }
  return stages;
}
