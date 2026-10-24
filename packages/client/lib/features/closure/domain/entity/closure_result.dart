import 'package:freezed_annotation/freezed_annotation.dart';

import 'closure_band.dart';
import 'closure_draft_flag.dart';
import 'closure_outcome.dart';

part 'closure_result.freezed.dart';

@freezed
abstract class ClosureResult with _$ClosureResult {
  const factory ClosureResult({
    required ClosureOutcome outcome,
    required ClosureBand band,
    required ClosureDraftFlag draftFlag,
    @Default([]) List<String> marks,
    String? story,

    /// The viewer left on their own and the author never judged them
    /// (#489): a [ClosureOutcome.notDone] here is how finalize settled
    /// them, not the author's mark.
    @Default(false) bool unjudgedLeaver,
  }) = _ClosureResult;

  const ClosureResult._();
}
