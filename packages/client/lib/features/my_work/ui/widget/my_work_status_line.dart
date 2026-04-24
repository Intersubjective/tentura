import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_card_deadline.dart';

/// Three semantic slots for the My Work single-line status row.
final class MyWorkStatusLineData {
  const MyWorkStatusLineData({
    required this.slot1,
    required this.slot2,
    required this.slot3,
    required this.timeSlotOverdue,
  });

  final String slot1;
  final String slot2;
  final String slot3;

  /// When true, [slot2] should use warning/error emphasis (deadline passed).
  final bool timeSlotOverdue;
}

/// Derives `slot1 · slot2 · slot3` for My Work cards (role-specific grammar).
MyWorkStatusLineData myWorkStatusLine({
  required L10n l10n,
  required MyWorkCardViewModel vm,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();

  return switch (vm.kind) {
    MyWorkCardKind.authoredDraft => _authoredDraft(l10n, vm, clock),
    MyWorkCardKind.authoredActive => _authoredActive(l10n, vm, clock),
    MyWorkCardKind.authoredClosed => _authoredClosed(l10n, vm, clock),
    MyWorkCardKind.committedActive => _committedActive(l10n, vm, clock),
    MyWorkCardKind.committedClosed => _committedClosed(l10n, vm, clock),
  };
}

MyWorkStatusLineData _authoredDraft(
  L10n l10n,
  MyWorkCardViewModel vm,
  DateTime now,
) {
  final b = vm.beacon;
  final time = _authoredTimeSlot(l10n, b, now);
  final slot3 = b.commitmentCount == 0
      ? l10n.myWorkStatusZeroCommitted
      : (b.commitmentCount == 1
          ? l10n.myWorkStatusOneCommitted
          : l10n.myWorkStatusNCommitted(b.commitmentCount));
  return MyWorkStatusLineData(
    slot1: l10n.myWorkStatusDraft,
    slot2: time.text,
    slot3: slot3,
    timeSlotOverdue: time.overdue,
  );
}

MyWorkStatusLineData _authoredActive(
  L10n l10n,
  MyWorkCardViewModel vm,
  DateTime now,
) {
  final b = vm.beacon;

  if (b.lifecycle == BeaconLifecycle.closedReviewOpen) {
    final n = b.commitmentCount;
    final slot3 = l10n.myWorkStatusNParticipants(n);
    return MyWorkStatusLineData(
      slot1: l10n.myWorkStatusClosed,
      slot2: l10n.myWorkStatusReviewOpen,
      slot3: slot3,
      timeSlotOverdue: false,
    );
  }

  final slot1 = _authoredRequestState(l10n, b);
  final time = _authoredTimeSlot(l10n, b, now);
  final slot3 = _authoredCoverageSlot(l10n, vm);
  return MyWorkStatusLineData(
    slot1: slot1,
    slot2: time.text,
    slot3: slot3,
    timeSlotOverdue: time.overdue,
  );
}

MyWorkStatusLineData _authoredClosed(
  L10n l10n,
  MyWorkCardViewModel vm,
  DateTime now,
) {
  final b = vm.beacon;
  final time = _authoredTimeSlot(l10n, b, now);
  final n = b.commitmentCount;
  final slot3 = l10n.myWorkStatusNParticipants(n);
  return MyWorkStatusLineData(
    slot1: l10n.myWorkStatusClosed,
    slot2: time.text,
    slot3: slot3,
    timeSlotOverdue: time.overdue,
  );
}

MyWorkStatusLineData _committedActive(
  L10n l10n,
  MyWorkCardViewModel vm,
  DateTime now,
) {
  final b = vm.beacon;

  if (vm.showReadyForReviewChip) {
    final slot1 = _committedSlot1WithOptionalResponse(
      l10n,
      vm,
      l10n.myWorkStatusReadyForReview,
    );
    return MyWorkStatusLineData(
      slot1: slot1,
      slot2: l10n.myWorkStatusMirrorClosed,
      slot3: l10n.myWorkStatusAcknowledgeContributions,
      timeSlotOverdue: false,
    );
  }

  final slot1 = _committedSlot1WithOptionalResponse(
    l10n,
    vm,
    l10n.myWorkStatusCommittedPersonal,
  );
  final time = _committedTimeSlot(l10n, b, now);
  final slot3 = _committedMirrorRequest(l10n, b);
  return MyWorkStatusLineData(
    slot1: slot1,
    slot2: time.text,
    slot3: slot3,
    timeSlotOverdue: time.overdue,
  );
}

MyWorkStatusLineData _committedClosed(
  L10n l10n,
  MyWorkCardViewModel vm,
  DateTime now,
) {
  final b = vm.beacon;
  final time = _committedTimeSlot(l10n, b, now);
  final slot3 = _committedMirrorRequest(l10n, b);
  final slot1 = _committedSlot1WithOptionalResponse(
    l10n,
    vm,
    l10n.myWorkStatusClosed,
  );
  return MyWorkStatusLineData(
    slot1: slot1,
    slot2: time.text,
    slot3: slot3,
    timeSlotOverdue: time.overdue,
  );
}

/// Puts the author's per-commit response in [commitmentStatusLabel] after the
/// commitment status, e.g. `committed: useful` (lowercased operands, locale-agnostic casing).
String _committedSlot1WithOptionalResponse(
  L10n l10n,
  MyWorkCardViewModel vm,
  String commitmentStatusLabel,
) {
  final resp = coordinationResponseLabel(l10n, vm.authorResponseType);
  if (resp == null) {
    return commitmentStatusLabel;
  }
  return l10n.myWorkStatusCommitmentWithResponse(
    commitmentStatusLabel.toLowerCase(),
    resp.toLowerCase(),
  );
}

String _authoredRequestState(L10n l10n, Beacon b) =>
    switch (b.coordinationStatus) {
      BeaconCoordinationStatus.noCommitmentsYet => l10n.myWorkStatusNoCommitments,
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded =>
        l10n.myWorkStatusNeedsMoreHelp,
      BeaconCoordinationStatus.commitmentsWaitingForReview =>
        l10n.myWorkStatusReviewingCommitments,
      BeaconCoordinationStatus.enoughHelpCommitted =>
        l10n.myWorkStatusEnoughHelp,
    };

/// Authored coverage / gap snapshot (beacon-level only; per-commit labels are
/// not available on the My Work fetch).
String _authoredCoverageSlot(L10n l10n, MyWorkCardViewModel vm) {
  final b = vm.beacon;
  final n = b.commitmentCount;
  if (b.coordinationStatus == BeaconCoordinationStatus.enoughHelpCommitted &&
      n > 0) {
    return l10n.myWorkStatusReadyToClose;
  }
  if (n == 0) {
    return l10n.myWorkStatusZeroCommitted;
  }
  if (n == 1) {
    return l10n.myWorkStatusOneCommitted;
  }
  return l10n.myWorkStatusNCommitted(n);
}

String _committedMirrorRequest(L10n l10n, Beacon b) {
  if (b.lifecycle.isClosedSection ||
      b.lifecycle == BeaconLifecycle.closedReviewOpen) {
    return l10n.myWorkStatusMirrorClosed;
  }
  return switch (b.coordinationStatus) {
    BeaconCoordinationStatus.noCommitmentsYet =>
      l10n.myWorkStatusMirrorNeedsMoreHelp,
    BeaconCoordinationStatus.moreOrDifferentHelpNeeded =>
      l10n.myWorkStatusMirrorNeedsMoreHelp,
    BeaconCoordinationStatus.commitmentsWaitingForReview =>
      l10n.myWorkStatusMirrorReviewingCommitments,
    BeaconCoordinationStatus.enoughHelpCommitted =>
      l10n.myWorkStatusMirrorEnoughHelp,
  };
}

({String text, bool overdue}) _authoredTimeSlot(
  L10n l10n,
  Beacon b,
  DateTime now,
) {
  final end = b.endAt;
  if (end != null) {
    return beaconCardCalendarDeadlineStatus(l10n, end, now: now)!;
  }
  if (b.lifecycle == BeaconLifecycle.pendingReview) {
    return (text: l10n.myWorkStatusAwaitingClose, overdue: false);
  }
  if (b.lifecycle == BeaconLifecycle.closedReviewOpen) {
    return (text: l10n.myWorkStatusReviewOpen, overdue: false);
  }
  return (text: l10n.myWorkStatusNoDeadline, overdue: false);
}

({String text, bool overdue}) _committedTimeSlot(
  L10n l10n,
  Beacon b,
  DateTime now,
) {
  final end = b.endAt;
  if (end != null) {
    return beaconCardCalendarDeadlineStatus(l10n, end, now: now)!;
  }
  if (b.lifecycle == BeaconLifecycle.pendingReview) {
    return (text: l10n.myWorkStatusWaitingOnAuthor, overdue: false);
  }
  return (text: l10n.myWorkStatusNoDeadline, overdue: false);
}
