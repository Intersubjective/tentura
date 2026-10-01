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
  }) = _ClosureResult;

  const ClosureResult._();
}
