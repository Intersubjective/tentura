import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';

/// #489 (Vadim, V1 = A): a member who left on their own and got no outcome
/// from the author (no row, or a row with a null outcome). They are out of
/// set A, as if marked «Не выполнено».
bool isUnjudgedLeaver(
  ClosureMemberRow member,
  Map<String, ClosureOutcome?> outcomes,
) => member.departure == Departure.voluntary && outcomes[member.userId] == null;

/// The members the author split covers: those the author did not mark
/// «Не выполнено», minus [isUnjudgedLeaver]s. This is "set A" in the #489
/// spec (Vadim, V1 = A). The one server rule used by the split writes and by
/// finalize.
Set<String> closureSplitEligibleMembers(
  Iterable<ClosureMemberRow> members,
  Map<String, ClosureOutcome?> outcomes,
) => {
  for (final m in members)
    if (outcomes[m.userId] != ClosureOutcome.notDone &&
        !isUnjudgedLeaver(m, outcomes))
      m.userId,
};
