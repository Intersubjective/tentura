import 'package:tentura_server/domain/closure/closure_band.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';

/// Closure role of a viewer (Arch §7). Blocked members and outsiders have no
/// role: they get "not found" for the state.
enum ClosureRole { author, voter, member }

/// What every role sees of a member. [departure] is author-only.
final class ClosureMemberView {
  const ClosureMemberView({
    required this.id,
    required this.notInRequest,
    this.departure,
  });

  final String id;
  final bool notInRequest;
  final String? departure;
}

/// Role-specific read model of `closureState`: each role's builder fills only
/// its allowlisted fields, the rest stay null.
final class ClosureStateView {
  const ClosureStateView({
    required this.epoch,
    required this.status,
    required this.role,
    required this.members,
    required this.closesAt,
    required this.myMarks,
    this.outcomes,
    this.split,
    this.mySupport,
    this.inCalcText,
    this.earlyCloseAt,
    this.canCloseNow,
    this.canReopen,
    this.extensionsUsed,
    this.story,
  });

  final int epoch;
  final ClosureEpochStatus status;
  final ClosureRole role;
  final List<ClosureMemberView> members;
  final DateTime closesAt;
  final List<String> myMarks;
  final Map<String, ClosureOutcome>? outcomes;
  final Map<String, int>? split;
  final List<String>? mySupport;
  final String? inCalcText;
  final DateTime? earlyCloseAt;
  final bool? canCloseNow;
  final bool? canReopen;
  final int? extensionsUsed;
  final String? story;
}

/// The viewer's own result: no share or helped value.
final class ClosureResultView {
  const ClosureResultView({
    required this.outcome,
    required this.band,
    required this.draftFlag,
    required this.marks,
    this.story,
  });

  final ClosureOutcome outcome;
  final ClosureBand band;
  final ClosureResultDraftFlag draftFlag;
  final List<String> marks;
  final String? story;
}
