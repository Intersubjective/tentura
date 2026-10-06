import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/beacon_plan.dart';

part 'plan_state.freezed.dart';

/// Who the Plan list shows.
enum PlanFilterKind { all, mine, person, unassigned }

@immutable
final class PlanFilter {
  const PlanFilter.all() : kind = PlanFilterKind.all, personId = null;

  const PlanFilter.mine() : kind = PlanFilterKind.mine, personId = null;

  const PlanFilter.unassigned()
    : kind = PlanFilterKind.unassigned,
      personId = null;

  const PlanFilter.person(String this.personId) : kind = PlanFilterKind.person;

  final PlanFilterKind kind;
  final String? personId;

  @override
  bool operator ==(Object other) =>
      other is PlanFilter && other.kind == kind && other.personId == personId;

  @override
  int get hashCode => Object.hash(kind, personId);
}

/// One-shot message for the Plan surface (snackbar).
sealed class PlanNotice {
  const PlanNotice();
}

/// A write failed; [error] is usually a `BeaconPlanException`.
final class PlanNoticeError extends PlanNotice {
  const PlanNoticeError(this.error, {this.tickFailed = false});

  final Object error;

  /// An optimistic tick was rolled back.
  final bool tickFailed;
}

@freezed
abstract class PlanState extends StateBase with _$PlanState {
  const factory PlanState({
    required String beaconId,
    required String viewerId,
    BeaconPlan? plan,
    @Default(PlanFilter.all()) PlanFilter filter,
    @Default(StateIsLoading()) StateStatus status,
    Object? loadError,

    /// Latest one-shot notice; [noticeSeq] grows with each one.
    PlanNotice? notice,
    @Default(0) int noticeSeq,

    /// Steps with a tick request in flight.
    @Default({}) Set<String> busyStepIds,
  }) = _PlanState;

  const PlanState._();
}
