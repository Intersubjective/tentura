import 'package:flutter/foundation.dart';
import 'package:tentura_root/domain/plan/plan.dart';

/// Which side wins one conflicting step.
enum PlanConflictChoice { mine, theirs }

/// A save that hit 1330 with step conflicts: what the user resolves.
@immutable
final class PlanConflict {
  const PlanConflict({
    required this.base,
    required this.theirs,
    required this.mine,
    required this.currentSeq,
    required this.stepIds,
  });

  /// The revision the draft started from.
  final PlanSnapshot base;

  /// The plan head now ([currentSeq]).
  final PlanSnapshot theirs;

  /// The local draft.
  final PlanSnapshot mine;
  final int currentSeq;

  /// Steps both sides changed differently, in plan order.
  final List<String> stepIds;

  /// Merges [mine] onto [theirs] with every conflicting step decided by
  /// [choices] (default: mine). The result is a full snapshot to save with
  /// base = [currentSeq]; it never conflicts again unless someone else
  /// saves meanwhile.
  PlanSnapshot resolve(Map<String, PlanConflictChoice> choices) {
    // Pretend the draft was based on their version of every conflicting
    // step: then «theirs» is unchanged there and the draft side wins, which
    // is either my content or a copy of theirs.
    final baseById = base.byId;
    final theirsById = theirs.byId;
    final mineById = mine.byId;
    final conflicting = stepIds.toSet();
    final patchedBase = PlanSnapshot([
      for (final s in base.steps)
        if (!conflicting.contains(s.id)) s else ?theirsById[s.id],
      for (final id in stepIds)
        if (!baseById.containsKey(id)) ?theirsById[id],
    ]);
    final patchedMine = PlanSnapshot([
      for (final s in mine.steps)
        if (!conflicting.contains(s.id) ||
            (choices[s.id] ?? PlanConflictChoice.mine) ==
                PlanConflictChoice.mine)
          s
        else
          ?theirsById[s.id],
      // Their version of a step I removed comes back when they win.
      for (final id in stepIds)
        if (!mineById.containsKey(id) &&
            choices[id] == PlanConflictChoice.theirs)
          ?theirsById[id],
    ]);
    return switch (PlanMerge.threeWay(patchedBase, theirs, patchedMine)) {
      PlanMergeMerged(:final snapshot) => snapshot,
      // Cannot happen after patching; fall back to the draft as is.
      PlanMergeConflict() => patchedMine,
    };
  }
}
