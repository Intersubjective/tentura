import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'entity/closure_outcome.dart';
import 'entity/closure_state.dart';

// Client port of the server's set-A rule and split arithmetic
// (`closure_finalize_case.dart` and `author_split.dart`), shared by the
// author editor and the silent preview so neither can drift from finalize.

/// Most people a hand-made split may cover (server `renormalize` limit).
const _maxA = 20;

/// Set A in [ids] order: members the author did not mark «Не выполнено»,
/// minus a voluntary leaver the author did not judge (#489).
List<String> closureSetA({
  required Iterable<String> ids,
  required Map<String, ClosureOutcome?> outcomes,
  Set<String> leftVoluntarily = const {},
}) => [
  for (final id in ids)
    if (outcomes[id] != ClosureOutcome.notDone &&
        !(outcomes[id] == null && leftVoluntarily.contains(id)))
      id,
];

/// Members of [data] who left on their own (author view only).
Set<String> closureVoluntaryLeavers(ClosureState data) => {
  for (final m in data.members)
    if (m.departure == 'voluntary') m.id,
};

/// [closureSetA] over the members of [data].
List<String> closureSetAOf(ClosureState data) => closureSetA(
  ids: [for (final m in data.members) m.id],
  outcomes: {for (final m in data.members) m.id: data.outcomes?[m.id]},
  leftVoluntarily: closureVoluntaryLeavers(data),
);

/// The author split finalize would settle with: [split] as saved, or, when it
/// still gives an unjudged voluntary leaver a share, renormalized over the
/// rest of A. `null` means equal shares.
Map<String, int>? closureSettledSplit({
  required Map<String, int>? split,
  required Map<String, ClosureOutcome?> outcomes,
  required String beaconId,
  Set<String> leftVoluntarily = const {},
}) {
  if (split == null || split.isEmpty) return null;
  final unjudgedLeavers = {
    for (final id in leftVoluntarily)
      if (outcomes.containsKey(id) && outcomes[id] == null) id,
  };
  if (!split.keys.any(unjudgedLeavers.contains)) return split;
  final next = renormalizeSplit(
    current: split,
    newA: closureSetA(
      ids: outcomes.keys,
      outcomes: outcomes,
      leftVoluntarily: leftVoluntarily,
    ).toSet(),
    beaconId: beaconId,
  );
  return next == null || next.isEmpty ? null : next;
}

/// Smallest share per member of a set A of [sizeOfA] people.
int closureMinPct(int sizeOfA) => sizeOfA <= 1 ? 0 : 5;

/// Server `renormalize`: [current] carried over to [newA]; a member missing
/// from [current] weighs `100 / |newA|`. `null` when [newA] is empty or
/// larger than 20.
Map<String, int>? renormalizeSplit({
  required Map<String, int>? current,
  required Set<String> newA,
  required String beaconId,
}) {
  if (current == null || newA.isEmpty || newA.length > _maxA) {
    return null;
  }
  if (newA.length == 1) return {newA.first: 100};
  final newcomerWeight = 100 / newA.length;
  return apportionSplit(
    total: 100,
    weights: {for (final id in newA) id: current[id] ?? newcomerWeight},
    min: closureMinPct(newA.length),
    beaconId: beaconId,
  );
}

/// Server `apportion`: water-fill [total] over [weights] with a floor of
/// [min], then round to steps of 5 by largest remainder (ties broken by
/// sha256 of `beaconId:helperId`, like the server).
Map<String, int> apportionSplit({
  required int total,
  required Map<String, num> weights,
  required int min,
  required String beaconId,
}) {
  if (weights.isEmpty) return {};
  final w = Map<String, num>.of(weights);
  if (w.values.every((v) => v == 0)) {
    for (final k in w.keys) {
      w[k] = 1;
    }
  }
  final targets = <String, double>{};
  final fixed = <String>{};
  while (true) {
    final unfixed = [
      for (final k in w.keys)
        if (!fixed.contains(k)) k,
    ];
    if (unfixed.isEmpty) break;
    final rem = total - min * fixed.length;
    final sumW = unfixed.fold<num>(0, (s, k) => s + w[k]!);
    var newlyFixed = false;
    for (final k in unfixed) {
      if (rem * w[k]! / sumW < min) {
        fixed.add(k);
        targets[k] = min.toDouble();
        newlyFixed = true;
      }
    }
    if (!newlyFixed) {
      for (final k in unfixed) {
        targets[k] = rem * w[k]! / sumW;
      }
      break;
    }
  }
  final units = {
    for (final k in w.keys) k: (targets[k]! / 5 + 1e-9).floor(),
  };
  final r = total ~/ 5 - units.values.fold<int>(0, (s, u) => s + u);
  if (r > 0) {
    final ranked = w.keys.toList()
      ..sort((a, b) {
        final cmp = (targets[b]! / 5 - units[b]!).compareTo(
          targets[a]! / 5 - units[a]!,
        );
        if (cmp != 0) return cmp;
        return _tieBreakKey(beaconId, a).compareTo(_tieBreakKey(beaconId, b));
      });
    for (var i = 0; i < r && i < ranked.length; i++) {
      units[ranked[i]] = units[ranked[i]]! + 1;
    }
  }
  return {for (final e in units.entries) e.key: e.value * 5};
}

/// Server `_tieBreakKey`: sha256 of `beaconId:helperId`, hex.
String _tieBreakKey(String beaconId, String helperId) =>
    sha256.convert(utf8.encode('$beaconId:$helperId')).toString();
