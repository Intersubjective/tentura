import 'closure_split.dart';
import 'entity/closure_outcome.dart';

const _rho = 0.3;
const _alphaA = 0.5;
const _beta = 0.5;

/// Client-side port of the server's silent settlement (Arch §5.5 with every
/// colleague support ignored): helper id -> share if nobody else says
/// anything. A `null` outcome (unanswered) counts like `cantJudge`, except
/// for a member in [leftVoluntarily]: they leave set A (#489). Set A and the
/// split come from `closure_split.dart`, the same rules finalize uses.
Map<String, double> silentPreview({
  required Map<String, ClosureOutcome?> outcomes,
  required Map<String, int>? split,
  required String beaconId,
  Set<String> leftVoluntarily = const {},
}) {
  final ids = outcomes.keys.toList()..sort();
  final n = ids.length;
  const poolH = 1 - _rho;
  final aSet = closureSetA(
    ids: ids,
    outcomes: outcomes,
    leftVoluntarily: leftVoluntarily,
  );
  final settled = closureSettledSplit(
    split: split,
    outcomes: outcomes,
    leftVoluntarily: leftVoluntarily,
    beaconId: beaconId,
  );
  final aPct = {for (final id in ids) id: 0.0};
  for (final id in aSet) {
    aPct[id] = settled == null
        ? 100.0 / aSet.length
        : (settled[id] ?? 0).toDouble();
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
