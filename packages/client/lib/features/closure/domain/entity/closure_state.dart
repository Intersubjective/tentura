import 'package:freezed_annotation/freezed_annotation.dart';

import 'closure_member.dart';
import 'closure_outcome.dart';
import 'closure_role.dart';

part 'closure_state.freezed.dart';

/// Server `ClosureEpochStatus.finalized`.
const _closureEpochFinalized = 1;

@freezed
abstract class ClosureState with _$ClosureState {
  const factory ClosureState({
    required int epoch,
    required int status,
    required ClosureRole role,
    required List<ClosureMember> members,
    required DateTime closesAt,

    /// Helper id -> outcome; null when the viewer may not see outcomes.
    Map<String, ClosureOutcome>? outcomes,

    /// Helper id -> percent; null when there is no custom split.
    Map<String, int>? split,
    @Default([]) List<String> mySupport,
    String? inCalcText,
    @Default([]) List<String> myMarks,
    DateTime? earlyCloseAt,
    @Default(false) bool canCloseNow,
    @Default(false) bool canReopen,
    String? story,

    /// Author only: how many times the deadline was extended (max 2).
    @Default(0) int extensionsUsed,
  }) = _ClosureState;

  const ClosureState._();

  /// The server sends [earlyCloseAt] only while a review window can matter
  /// (`ClosureCase.earlyCloseAt`, #632). A voter or the author on a finalized
  /// epoch with no such date closed without a final check (#825). A member
  /// omits the field, so a leaver is not treated as a skipped review.
  bool get hadNoFinalCheck =>
      status == _closureEpochFinalized &&
      earlyCloseAt == null &&
      (role == ClosureRole.author || role == ClosureRole.voter);
}
