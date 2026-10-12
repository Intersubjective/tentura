import 'plan_diff.dart';
import 'plan_snapshot.dart';

sealed class PlanMergeResult {
  const PlanMergeResult();
}

/// The merge produced one snapshot. [theirChangedStepIds] are the steps the
/// other side changed meanwhile (for the «merged» notice).
final class PlanMergeMerged extends PlanMergeResult {
  const PlanMergeMerged(this.snapshot, this.theirChangedStepIds);

  final PlanSnapshot snapshot;
  final Set<String> theirChangedStepIds;
}

/// Both sides changed the same steps differently; nothing can be written.
final class PlanMergeConflict extends PlanMergeResult {
  const PlanMergeConflict(this.stepIds);

  final List<String> stepIds;
}

abstract final class PlanMerge {
  /// Three-way merge of plan drafts by step (decision 4, #220).
  ///
  /// For every step id: if only one side changed it relative to [base], that
  /// side wins; if both changed it to different values, it conflicts. Adding
  /// and removing count as changes; two removals agree. Order never
  /// conflicts: the result follows [theirs], and every step I moved or added
  /// is placed right after its predecessor in [mine].
  static PlanMergeResult threeWay(
    PlanSnapshot base,
    PlanSnapshot theirs,
    PlanSnapshot mine,
  ) {
    final b = base.byId;
    final t = theirs.byId;
    final m = mine.byId;
    final ids = <String>{...base.ids, ...theirs.ids, ...mine.ids};
    final conflicts = <String>[];
    final theirChanged = <String>{};
    final resolved = <String, PlanStepSnapshot?>{};
    for (final id in ids) {
      final bs = b[id];
      final ts = t[id];
      final ms = m[id];
      final mineChanged = !_sameStep(bs, ms);
      final theirsChanged = !_sameStep(bs, ts);
      if (theirsChanged) theirChanged.add(id);
      if (mineChanged && theirsChanged && !_sameStep(ms, ts)) {
        conflicts.add(id);
        continue;
      }
      if (mineChanged) {
        resolved[id] = ms;
      } else {
        resolved[id] = ts;
      }
    }
    if (conflicts.isNotEmpty) {
      return PlanMergeConflict(
        <String>{
          for (final id in [...mine.ids, ...theirs.ids, ...base.ids])
            if (conflicts.contains(id)) id,
        }.toList(),
      );
    }

    // Order: start from theirs, then re-place steps I moved or added.
    final order = [
      for (final id in theirs.ids)
        if (resolved[id] != null) id,
    ];
    final movedByMe = planMovedStepIds(base, mine);
    final movedByThem = planMovedStepIds(base, theirs);
    final baseIds = base.ids.toSet();

    for (final id in mine.ids) {
      if (resolved[id] == null) continue;
      final added = !baseIds.contains(id) && !t.containsKey(id);
      final moved = movedByMe.contains(id) && !movedByThem.contains(id);
      final missing = !order.contains(id);
      if (!(added || missing || moved)) continue;
      order.remove(id);
      // Nearest earlier step of mine that is still in the result.
      var anchorIndex = -1;
      final myIndex = mine.ids.indexOf(id);
      for (var i = myIndex - 1; i >= 0; i--) {
        final at = order.indexOf(mine.ids[i]);
        if (at >= 0) {
          anchorIndex = at;
          break;
        }
      }
      order.insert(anchorIndex + 1, id);
    }

    return PlanMergeMerged(
      PlanSnapshot([for (final id in order) resolved[id]!]),
      theirChanged,
    );
  }
}

bool _sameStep(PlanStepSnapshot? a, PlanStepSnapshot? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.sameContentAs(b);
}
