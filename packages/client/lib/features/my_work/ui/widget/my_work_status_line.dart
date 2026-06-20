import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_anchor_status.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/duration_format.dart';

/// Two semantic slots for the My Work status row (`slot1 [· slot2]`).
final class MyWorkStatusLineData {
  const MyWorkStatusLineData({
    required this.slot1,
    required this.slot2,
    required this.timeSlotOverdue,
    this.slot1ResponseType,
    this.slot1CoordinationStatus,
  });

  final String slot1;
  final String slot2;

  /// When set, [slot1] is tinted for the viewer's help-offered-card author reaction.
  final CoordinationResponseType? slot1ResponseType;

  /// When set, [slot1] is tinted for the authored card beacon coordination state.
  final BeaconCoordinationStatus? slot1CoordinationStatus;

  /// Reserved for future emphasis on expired review window (currently unused).
  final bool timeSlotOverdue;

  bool get isEmpty => slot1.trim().isEmpty && slot2.trim().isEmpty;
}

/// Assembles `slot1 [· slot2]` for compact header / app bar subtitles.
String myWorkStatusDisplayLine(
  MyWorkStatusLineData data, {
  String? roomSubtitle,
}) {
  var slot2 = data.slot2.trim();
  if (slot2.isEmpty) {
    slot2 = roomSubtitle?.trim() ?? '';
  }
  final slot1 = data.slot1.trim();
  if (slot1.isEmpty && slot2.isEmpty) return '';
  if (slot1.isEmpty) return slot2;
  if (slot2.isEmpty) return slot1;
  return '$slot1 · $slot2';
}

TenturaTone myWorkStatusTone(MyWorkStatusLineData data) {
  final response = data.slot1ResponseType;
  if (response != null) {
    return coordinationResponseTone(response);
  }
  final coord = data.slot1CoordinationStatus;
  if (coord != null) {
    return beaconAnchorStatusTone(coord);
  }
  return TenturaTone.neutral;
}

/// Derives `slot1 [· slot2]` for My Work cards (role-specific grammar).
MyWorkStatusLineData myWorkStatusLine({
  required L10n l10n,
  required MyWorkCardViewModel vm,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();

  return switch (vm.kind) {
    MyWorkCardKind.authoredDraft => _empty(),
    MyWorkCardKind.authoredActive => _authoredActive(l10n, vm, clock),
    MyWorkCardKind.authoredFinished => _authoredFinished(l10n, vm),
    MyWorkCardKind.authoredArchived => _authoredFinished(l10n, vm),
    MyWorkCardKind.helpOfferedActive => _helpOfferedActive(l10n, vm, clock),
    MyWorkCardKind.helpOfferedFinished => _helpOfferedFinished(l10n, vm),
    MyWorkCardKind.helpOfferedArchived => _helpOfferedFinished(l10n, vm),
  };
}

MyWorkStatusLineData _empty() => const MyWorkStatusLineData(
      slot1: '',
      slot2: '',
      timeSlotOverdue: false,
    );

MyWorkStatusLineData _authoredActive(
  L10n l10n,
  MyWorkCardViewModel vm,
  DateTime now,
) {
  final b = vm.beacon;

  if (b.lifecycle == BeaconLifecycle.reviewOpen) {
    final review = _reviewWindowSlot(l10n, b, now);
    return MyWorkStatusLineData(
      slot1: l10n.myWorkStatusWrappingUp,
      slot2: review.text,
      timeSlotOverdue: review.overdue,
    );
  }

  return switch (b.coordinationStatus) {
    BeaconCoordinationStatus.neutral => _empty(),
    BeaconCoordinationStatus.moreOrDifferentHelpNeeded => MyWorkStatusLineData(
        slot1: l10n.myWorkStatusNeedsMoreHelp,
        slot2: '',
        timeSlotOverdue: false,
        slot1CoordinationStatus: BeaconCoordinationStatus.moreOrDifferentHelpNeeded,
      ),
    BeaconCoordinationStatus.enoughHelpOffered => MyWorkStatusLineData(
        slot1: l10n.myWorkStatusEnoughHelp,
        slot2: '',
        timeSlotOverdue: false,
        slot1CoordinationStatus: BeaconCoordinationStatus.enoughHelpOffered,
      ),
  };
}

MyWorkStatusLineData _authoredFinished(L10n l10n, MyWorkCardViewModel vm) {
  final b = vm.beacon;
  final slot1 = b.lifecycle == BeaconLifecycle.cancelled
      ? l10n.myWorkStatusCancelled
      : l10n.myWorkStatusClosed;
  return MyWorkStatusLineData(
    slot1: slot1,
    slot2: '',
    timeSlotOverdue: false,
  );
}

MyWorkStatusLineData _helpOfferedActive(
  L10n l10n,
  MyWorkCardViewModel vm,
  DateTime now,
) {
  final b = vm.beacon;

  if (b.lifecycle == BeaconLifecycle.reviewOpen) {
    final review = _reviewWindowSlot(l10n, b, now);
    return MyWorkStatusLineData(
      slot1: l10n.myWorkStatusWrappingUp,
      slot2: review.text,
      timeSlotOverdue: review.overdue,
      slot1ResponseType: vm.authorResponseType,
    );
  }

  if (vm.authorResponseType != null) {
    final slot1 = _helpOfferedSlot1WithOptionalResponse(
      l10n,
      vm,
      l10n.myWorkStatusHelpOfferedPersonal,
    );
    return MyWorkStatusLineData(
      slot1: slot1,
      slot2: '',
      timeSlotOverdue: false,
      slot1ResponseType: vm.authorResponseType,
    );
  }

  return switch (b.coordinationStatus) {
    BeaconCoordinationStatus.neutral => _empty(),
    BeaconCoordinationStatus.moreOrDifferentHelpNeeded => MyWorkStatusLineData(
        slot1: l10n.myWorkStatusNeedsMoreHelp,
        slot2: '',
        timeSlotOverdue: false,
      ),
    BeaconCoordinationStatus.enoughHelpOffered => MyWorkStatusLineData(
        slot1: l10n.myWorkStatusEnoughHelp,
        slot2: '',
        timeSlotOverdue: false,
      ),
  };
}

MyWorkStatusLineData _helpOfferedFinished(L10n l10n, MyWorkCardViewModel vm) {
  final b = vm.beacon;
  final statusLabel = b.lifecycle == BeaconLifecycle.cancelled
      ? l10n.myWorkStatusCancelled
      : l10n.myWorkStatusClosed;
  final slot1 = _helpOfferedSlot1WithOptionalResponse(
    l10n,
    vm,
    statusLabel,
  );
  return MyWorkStatusLineData(
    slot1: slot1,
    slot2: '',
    timeSlotOverdue: false,
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

({String text, bool overdue}) _reviewWindowSlot(
  L10n l10n,
  Beacon b,
  DateTime now,
) {
  final closesAt = b.reviewClosesAt;
  if (closesAt == null || b.reviewWindowStatus == 1) {
    return (text: '', overdue: false);
  }
  final remaining = closesAt.toUtc().difference(now.toUtc());
  if (remaining.isNegative) {
    return (text: '', overdue: false);
  }
  return (
    text: formatCompactDurationRemaining(remaining, l10n),
    overdue: false,
  );
}
