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

/// Set A (the author split covers exactly these): members the author did not
/// mark «Не выполнено», minus [isUnjudgedLeaver]s. The one server rule used
/// by the split writes and by finalize.
Set<String> closureSetA(
  Iterable<ClosureMemberRow> members,
  Map<String, ClosureOutcome?> outcomes,
) => {
  for (final m in members)
    if (outcomes[m.userId] != ClosureOutcome.notDone &&
        !isUnjudgedLeaver(m, outcomes))
      m.userId,
};
