import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/plan_revision.dart';

part 'plan_history_state.freezed.dart';

@freezed
abstract class PlanHistoryState extends StateBase with _$PlanHistoryState {
  const factory PlanHistoryState({
    @Default([]) List<PlanRevisionEntry> items,
    @Default({}) Map<String, String> names,
    int? nextBeforeSeq,
    @Default(StateIsLoading()) StateStatus status,
    Object? loadError,

    /// Revision opened for preview, with its content once loaded.
    int? previewSeq,
    PlanRevisionSnapshot? preview,
    @Default(false) bool restoring,

    /// Set after a successful restore (the version restored).
    int? restoredFromSeq,
    @Default(0) int restoredSeq,

    /// Latest write error; [errorSeq] grows with each one.
    Object? error,
    @Default(0) int errorSeq,
  }) = _PlanHistoryState;

  const PlanHistoryState._();

  /// Head revision: the base of a restore. Always the newest row.
  int get headSeq => items.isEmpty ? 0 : items.first.seq;
}
