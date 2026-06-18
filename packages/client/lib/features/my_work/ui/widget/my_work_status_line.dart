import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Three semantic slots for the My Work single-line status row.
final class MyWorkStatusLineData {
  const MyWorkStatusLineData({
    required this.slot1,
    required this.slot2,
    required this.slot3,
    required this.timeSlotOverdue,
    this.slot1ResponseType,
    this.slot1CoordinationStatus,
  });

  final String slot1;
  final String slot2;
  final String slot3;

  /// When set, [slot1] is tinted for the viewer's help-offered-card author reaction.
  final CoordinationResponseType? slot1ResponseType;

  /// When set, [slot1] is tinted for the authored card beacon coordination state.
  final BeaconCoordinationStatus? slot1CoordinationStatus;

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
    MyWorkCardKind.helpOfferedActive => _helpOfferedActive(l10n, vm, clock),
    MyWorkCardKind.helpOfferedClosed => _helpOfferedClosed(l10n, vm, clock),
  };
}

MyWorkStatusLineData _authoredDraft(
  L10n l10n,
  MyWorkCardViewModel vm,
  DateTime now,
) {
  final b = vm.beacon;
  final time = _authoredTimeSlot(l10n, b, now);
  final slot3 = b.helpOfferCount == 0
      ? l10n.myWorkStatusZeroHelpOffered
      : (b.helpOfferCount == 1
          ? l10n.myWorkStatusOneHelpOffered
          : l10n.myWorkStatusNHelpOffered(b.helpOfferCount));
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
    final n = b.helpOfferCount;
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
    slot1CoordinationStatus: b.coordinationStatus,
  );
}

MyWorkStatusLineData _authoredClosed(
  L10n l10n,
  MyWorkCardViewModel vm,
  DateTime now,
) {
  final b = vm.beacon;
  final time = _authoredTimeSlot(l10n, b, now);
  final n = b.helpOfferCount;
  final slot3 = l10n.myWorkStatusNParticipants(n);
  return MyWorkStatusLineData(
    slot1: l10n.myWorkStatusClosed,
    slot2: time.text,
    slot3: slot3,
    timeSlotOverdue: time.overdue,
  );
}

MyWorkStatusLineData _helpOfferedActive(
  L10n l10n,
  MyWorkCardViewModel vm,
  DateTime now,
) {
  final b = vm.beacon;

  if (vm.showReadyForReviewChip) {
    final slot1 = _helpOfferedSlot1WithOptionalResponse(
      l10n,
      vm,
      l10n.myWorkStatusReadyForReview,
    );
    return MyWorkStatusLineData(
      slot1: slot1,
      slot2: l10n.myWorkStatusMirrorClosed,
      slot3: l10n.myWorkStatusAcknowledgeContributions,
      timeSlotOverdue: false,
      slot1ResponseType: vm.authorResponseType,
    );
  }

  final slot1 = _helpOfferedSlot1WithOptionalResponse(
    l10n,
    vm,
    l10n.myWorkStatusHelpOfferedPersonal,
  );
  final time = _helpOfferedTimeSlot(l10n, b, now);
  final slot3 = _helpOfferedMirrorRequest(l10n, b);
  return MyWorkStatusLineData(
    slot1: slot1,
    slot2: time.text,
    slot3: slot3,
    timeSlotOverdue: time.overdue,
    slot1ResponseType: vm.authorResponseType,
  );
}

MyWorkStatusLineData _helpOfferedClosed(
  L10n l10n,
  MyWorkCardViewModel vm,
  DateTime now,
) {
  final b = vm.beacon;
  final time = _helpOfferedTimeSlot(l10n, b, now);
  final slot3 = _helpOfferedMirrorRequest(l10n, b);
  final slot1 = _helpOfferedSlot1WithOptionalResponse(
    l10n,
    vm,
    l10n.myWorkStatusClosed,
  );
  return MyWorkStatusLineData(
    slot1: slot1,
    slot2: time.text,
    slot3: slot3,
    timeSlotOverdue: time.overdue,
    slot1ResponseType: vm.authorResponseType,
  );
}

/// Puts the author's per-help-offer response in [helpOfferStatusLabel] after the
/// help offer status, e.g. `help offered: useful` (lowercased operands, locale-agnostic casing).
String _helpOfferedSlot1WithOptionalResponse(
  L10n l10n,
  MyWorkCardViewModel vm,
  String helpOfferStatusLabel,
) {
  final resp = coordinationResponseLabel(l10n, vm.authorResponseType);
  if (resp == null) {
    return helpOfferStatusLabel;
  }
  return l10n.myWorkStatusHelpOfferWithResponse(
    helpOfferStatusLabel.toLowerCase(),
    resp.toLowerCase(),
  );
}

String _authoredRequestState(L10n l10n, Beacon b) =>
    switch (b.coordinationStatus) {
      BeaconCoordinationStatus.noHelpOffersYet => l10n.myWorkStatusNoHelpOffers,
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded =>
        l10n.myWorkStatusNeedsMoreHelp,
      BeaconCoordinationStatus.helpOffersWaitingForReview =>
        l10n.myWorkStatusReviewingHelpOffers,
      BeaconCoordinationStatus.enoughHelpOffered =>
        l10n.myWorkStatusEnoughHelp,
    };

/// Authored coverage / gap snapshot (beacon-level only; per-help-offer labels are
/// not available on the My Work fetch).
String _authoredCoverageSlot(L10n l10n, MyWorkCardViewModel vm) {
  final b = vm.beacon;
  final n = b.helpOfferCount;
  if (b.coordinationStatus == BeaconCoordinationStatus.enoughHelpOffered &&
      n > 0) {
    return l10n.myWorkStatusReadyToClose;
  }
  if (n == 0) {
    return l10n.myWorkStatusZeroHelpOffered;
  }
  if (n == 1) {
    return l10n.myWorkStatusOneHelpOffered;
  }
  return l10n.myWorkStatusNHelpOffered(n);
}

String _helpOfferedMirrorRequest(L10n l10n, Beacon b) {
  if (b.lifecycle.isClosedSection ||
      b.lifecycle == BeaconLifecycle.closedReviewOpen) {
    return l10n.myWorkStatusMirrorClosed;
  }
  return switch (b.coordinationStatus) {
    BeaconCoordinationStatus.noHelpOffersYet =>
      l10n.myWorkStatusMirrorNeedsMoreHelp,
    BeaconCoordinationStatus.moreOrDifferentHelpNeeded =>
      l10n.myWorkStatusMirrorNeedsMoreHelp,
    BeaconCoordinationStatus.helpOffersWaitingForReview =>
      l10n.myWorkStatusMirrorReviewingHelpOffers,
    BeaconCoordinationStatus.enoughHelpOffered =>
      l10n.myWorkStatusMirrorEnoughHelp,
  };
}

({String text, bool overdue}) _authoredTimeSlot(
  L10n l10n,
  Beacon b,
  DateTime now,
) {
  if (b.hasScheduleDates) {
    return (text: '', overdue: false);
  }
  if (b.lifecycle == BeaconLifecycle.pendingReview) {
    return (text: l10n.myWorkStatusAwaitingClose, overdue: false);
  }
  if (b.lifecycle == BeaconLifecycle.closedReviewOpen) {
    return (text: l10n.myWorkStatusReviewOpen, overdue: false);
  }
  return (text: l10n.myWorkStatusNoDeadline, overdue: false);
}

({String text, bool overdue}) _helpOfferedTimeSlot(
  L10n l10n,
  Beacon b,
  DateTime now,
) {
  if (b.hasScheduleDates) {
    return (text: '', overdue: false);
  }
  if (b.lifecycle == BeaconLifecycle.pendingReview) {
    return (text: l10n.myWorkStatusWaitingOnAuthor, overdue: false);
  }
  return (text: l10n.myWorkStatusNoDeadline, overdue: false);
}
