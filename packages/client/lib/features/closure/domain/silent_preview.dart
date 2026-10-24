import 'entity/closure_outcome.dart';

const _rho = 0.3;
const _alphaA = 0.5;
const _beta = 0.5;

/// Client-side port of the server's silent settlement (Arch §5.5 with every
/// colleague support ignored): helper id -> share if nobody else says
/// anything. A `null` outcome (unanswered) counts like `cantJudge`, except
/// for a member in [leftVoluntarily]: they get no author share (#489).
Map<String, double> silentPreview({
  required Map<String, ClosureOutcome?> outcomes,
  required Map<String, int>? split,
  Set<String> leftVoluntarily = const {},
}) {
  final ids = outcomes.keys.toList()..sort();
  final n = ids.length;
  const poolH = 1 - _rho;
  final aSet = [
    for (final id in ids)
      if (outcomes[id] != ClosureOutcome.notDone &&
          !(outcomes[id] == null && leftVoluntarily.contains(id)))
        id,
  ];
  // A split that still gives the dropped leaver a share is rescaled over
  // the rest, like the server's renormalize (without its 5% rounding).
  final splitSum = split == null
      ? 0
      : aSet.fold<int>(0, (sum, id) => sum + (split[id] ?? 0));
  final aPct = {for (final id in ids) id: 0.0};
  for (final id in aSet) {
    aPct[id] = split == null
        ? 100.0 / aSet.length
        : splitSum == 0
        ? 0.0
        : (split[id] ?? 0) * 100 / splitSum;
  }
  final silent = {for (final id in ids) id: 0.0};
  if (aSet.isEmpty) return silent;

  final alpha = n >= 3 ? _alphaA : 1.0;
  for (final id in ids) {
    silent[id] = alpha * poolH * aPct[id]! / 100;
  }
  for (final voter in ids) {
    final slice =
        (1 - alpha) * poolH * (_beta / n + (1 - _beta) * aPct[voter]! / 100);
    var s = 0.0;
    for (final o in ids) {
      if (o != voter) s += aPct[o]!;
    }
    if (s == 0) continue;
    for (final o in ids) {
      if (o != voter) silent[o] = silent[o]! + slice * aPct[o]! / s;
    }
  }
  return silent;
}
