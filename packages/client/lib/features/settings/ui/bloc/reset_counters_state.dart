import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'reset_counters_state.freezed.dart';

/// What one run of **Reset counters** ended in.
///
/// There are two, and only two. D15 forbids a third: a repair that came back
/// with work still on it is [refreshed], because a correct result may still
/// contain dots and counts.
enum ResetCountersOutcome { refreshed, failed }

@freezed
abstract class ResetCountersState extends StateBase with _$ResetCountersState {
  const factory ResetCountersState({
    /// D15 — progress while it runs; also the guard that stops a second
    /// in-flight call.
    @Default(false) bool isRunning,
    ResetCountersOutcome? outcome,

    /// U17d — how many outstanding actions the repair could **not** fix.
    ///
    /// Not a failure and not work the user owes: it is the server saying
    /// these rows cannot be reconciled from their source at all. Zero after
    /// a run that failed, because a run that never answered knows nothing.
    @Default(0) int unrepairableCount,

    /// Bumped once per finished run, so two identical outcomes in a row are
    /// still two events a listener can tell apart.
    @Default(0) int outcomeSerial,
  }) = _ResetCountersState;

  const ResetCountersState._();
}
