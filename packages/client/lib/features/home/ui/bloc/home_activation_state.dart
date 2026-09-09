import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';

part 'home_activation_state.freezed.dart';

@freezed
abstract class HomeActivationState with _$HomeActivationState {
  const factory HomeActivationState({
    @Default(HomeActivationSignals()) HomeActivationSignals signals,
    @Default(false) bool activatedLatch,
    @Default(false) bool dismissedLatch,
    @Default(OrientationDebugOverride.auto)
    OrientationDebugOverride debugOverride,
    @Default('') String boundAccountId,
    @Default(false) bool hydrated,
  }) = _HomeActivationState;

  const HomeActivationState._();

  OrientationDecision decideFor(MyWorkFilter filter) {
    if (filter != MyWorkFilter.active) return OrientationDecision.ordinaryEmpty;
    if (boundAccountId.isEmpty) {
      return hydrated
          ? OrientationDecision.ordinaryEmpty
          : OrientationDecision.undecided;
    }
    if (!hydrated) return OrientationDecision.undecided;
    switch (debugOverride) {
      case OrientationDebugOverride.show:
        return OrientationDecision.show;
      case OrientationDebugOverride.hide:
        return OrientationDecision.ordinaryEmpty;
      case OrientationDebugOverride.auto:
        if (dismissedLatch || activatedLatch) {
          return OrientationDecision.ordinaryEmpty;
        }
        if (signals.inboxFailed) return OrientationDecision.ordinaryEmpty;
        if (!signals.isSettled) return OrientationDecision.undecided;
        return signals.hasActivity
            ? OrientationDecision.ordinaryEmpty
            : OrientationDecision.show;
    }
  }
}
