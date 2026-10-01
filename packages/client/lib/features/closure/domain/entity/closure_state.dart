import 'package:freezed_annotation/freezed_annotation.dart';

import 'closure_member.dart';
import 'closure_outcome.dart';
import 'closure_role.dart';

part 'closure_state.freezed.dart';

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
  }) = _ClosureState;

  const ClosureState._();
}
