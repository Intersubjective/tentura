import 'package:flutter/foundation.dart';
import 'package:tentura_root/domain/plan/plan.dart';

/// A step someone else changed while the draft was open, and both sides
/// changed it: the draft now carries their version.
@immutable
final class PlanConflictStep {
  const PlanConflictStep({
    required this.stepId,
    required this.title,
    this.actorId,
    this.actorName,
  });

  final String stepId;

  /// The step's title (their version, else the last one known).
  final String title;

  /// Who changed it, when the history says so.
  final String? actorId;

  /// [actorId]'s display name from the server, when it sent one.
  final String? actorName;
}

/// The draft moved onto the current plan after a save conflict (1330).
@immutable
final class PlanRebase {
  const PlanRebase({
    required this.currentSeq,
    required this.theirs,
    required this.draft,
    this.conflicts = const [],
  });

  /// The plan head the draft is now based on.
  final int currentSeq;

  /// Content of [currentSeq].
  final PlanSnapshot theirs;

  /// The user's edits re-applied onto [theirs]; conflicting steps carry
  /// their version.
  final PlanSnapshot draft;

  /// Steps both sides changed, in plan order; empty when everything merged.
  final List<PlanConflictStep> conflicts;
}

/// [mine] with each step of [stepIds] replaced by its version in [theirs]
/// (dropped when they removed it, put back when only I removed it).
PlanSnapshot planTakeTheirSteps(
  PlanSnapshot mine,
  PlanSnapshot theirs,
  List<String> stepIds,
) {
  final taken = stepIds.toSet();
  final theirsById = theirs.byId;
  final steps = [
    for (final s in mine.steps)
      if (!taken.contains(s.id)) s else ?theirsById[s.id],
  ];
  final present = {for (final s in steps) s.id};
  for (final id in stepIds) {
    final their = theirsById[id];
    if (their == null || present.contains(id)) continue;
    // Right after its nearest earlier neighbour in their plan.
    final theirIds = theirs.ids;
    var at = 0;
    for (var i = theirIds.indexOf(id) - 1; i >= 0; i--) {
      final j = steps.indexWhere((s) => s.id == theirIds[i]);
      if (j >= 0) {
        at = j + 1;
        break;
      }
    }
    steps.insert(at, their);
    present.add(id);
  }
  return PlanSnapshot(steps);
}
