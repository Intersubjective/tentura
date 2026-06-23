import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';

import '../ui/util/beacon_closure_readiness.dart';

/// Stable row ids for the beacon status bottom sheet (fixed display order).
enum BeaconStatusMenuRowId {
  draft,
  open,
  moreHelp,
  enoughHelp,
  wrappingUp,
  closed,
  cancelled,
}

/// Action dispatched when the user taps an enabled row (or secondary control).
enum BeaconStatusMenuAction {
  none,
  publish,
  setCoordinationNeutral,
  setCoordinationMoreHelp,
  setCoordinationEnoughHelp,
  startWrappingUp,
  closeDirect,
  closeNow,
  extendReview,
  reopen,
  cancel,
}

/// Keys mapped to l10n in [beaconStatusMenuDisabledReasonLabel].
enum BeaconStatusMenuDisabledReason {
  none,
  publishFirst,
  finishReviewFirst,
  noCommitters,
  cancelHasOffers,
  cancelWrappingUp,
  blocked,
  notReadyToClose,
  waitingForReviewers,
  lifecycleAuthorOnly,
  terminalState,
}

class ReviewWindowMenuSnapshot {
  const ReviewWindowMenuSnapshot({
    required this.reviewedCount,
    required this.totalCount,
    required this.windowComplete,
    required this.extensionsUsed,
    this.maxExtensions = kMaxBeaconReviewExtensions,
  });

  static const int kMaxBeaconReviewExtensions = 2;

  final int reviewedCount;
  final int totalCount;
  final bool windowComplete;
  final int extensionsUsed;
  final int maxExtensions;

  bool get canExtend => extensionsUsed < maxExtensions;

  bool get canCloseNow =>
      !windowComplete &&
      totalCount > 0 &&
      reviewedCount >= totalCount;
}

class BeaconStatusMenuInput {
  const BeaconStatusMenuInput({
    required this.beacon,
    required this.closureReadiness,
    required this.hasCommitters,
    required this.canManageLifecycle,
    required this.canSetCoordination,
    this.reviewWindow,
    this.allowForceCloseWhenBlocked = false,
  });

  final Beacon beacon;
  final BeaconClosureReadiness closureReadiness;
  final bool hasCommitters;
  final bool canManageLifecycle;
  final bool canSetCoordination;
  final ReviewWindowMenuSnapshot? reviewWindow;
  final bool allowForceCloseWhenBlocked;
}

class BeaconStatusMenuRow {
  const BeaconStatusMenuRow({
    required this.id,
    required this.action,
    required this.isSelected,
    required this.isEnabled,
    this.disabledReason = BeaconStatusMenuDisabledReason.none,
    this.secondaryAction = BeaconStatusMenuAction.none,
    this.isSecondaryEnabled = false,
  });

  final BeaconStatusMenuRowId id;
  final BeaconStatusMenuAction action;
  final bool isSelected;
  final bool isEnabled;
  final BeaconStatusMenuDisabledReason disabledReason;
  final BeaconStatusMenuAction secondaryAction;
  final bool isSecondaryEnabled;
}

List<BeaconStatusMenuRow> buildBeaconStatusMenuRows(
  BeaconStatusMenuInput input,
) {
  final lifecycle = input.beacon.lifecycle;

  if (lifecycle == BeaconLifecycle.closed ||
      lifecycle == BeaconLifecycle.cancelled) {
    return _terminalRows(lifecycle);
  }

  return [
    _draftRow(input),
    _openRow(input),
    _moreHelpRow(input),
    _enoughHelpRow(input),
    _wrappingUpRow(input),
    _closedRow(input),
    _cancelledRow(input),
  ];
}

List<BeaconStatusMenuRow> _terminalRows(BeaconLifecycle lifecycle) {
  BeaconStatusMenuRow row(
    BeaconStatusMenuRowId id, {
    required bool selected,
  }) =>
      BeaconStatusMenuRow(
        id: id,
        action: BeaconStatusMenuAction.none,
        isSelected: selected,
        isEnabled: false,
        disabledReason: BeaconStatusMenuDisabledReason.terminalState,
      );

  return [
    row(BeaconStatusMenuRowId.draft, selected: false),
    row(BeaconStatusMenuRowId.open, selected: false),
    row(BeaconStatusMenuRowId.moreHelp, selected: false),
    row(BeaconStatusMenuRowId.enoughHelp, selected: false),
    row(BeaconStatusMenuRowId.wrappingUp, selected: false),
    row(
      BeaconStatusMenuRowId.closed,
      selected: lifecycle == BeaconLifecycle.closed,
    ),
    row(
      BeaconStatusMenuRowId.cancelled,
      selected: lifecycle == BeaconLifecycle.cancelled,
    ),
  ];
}

BeaconStatusMenuRow _draftRow(BeaconStatusMenuInput input) {
  final selected = input.beacon.lifecycle == BeaconLifecycle.draft;
  return BeaconStatusMenuRow(
    id: BeaconStatusMenuRowId.draft,
    action: BeaconStatusMenuAction.none,
    isSelected: selected,
    isEnabled: false,
    disabledReason: selected
        ? BeaconStatusMenuDisabledReason.none
        : BeaconStatusMenuDisabledReason.terminalState,
  );
}

BeaconStatusMenuRow _openRow(BeaconStatusMenuInput input) {
  final lifecycle = input.beacon.lifecycle;
  final coord = input.beacon.coordinationStatus;

  if (lifecycle == BeaconLifecycle.draft) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.open,
      action: BeaconStatusMenuAction.publish,
      isSelected: false,
      isEnabled: input.canManageLifecycle,
      disabledReason: input.canManageLifecycle
          ? BeaconStatusMenuDisabledReason.none
          : BeaconStatusMenuDisabledReason.lifecycleAuthorOnly,
    );
  }

  if (lifecycle == BeaconLifecycle.reviewOpen) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.open,
      action: BeaconStatusMenuAction.reopen,
      isSelected: false,
      isEnabled: input.canManageLifecycle,
      disabledReason: input.canManageLifecycle
          ? BeaconStatusMenuDisabledReason.none
          : BeaconStatusMenuDisabledReason.lifecycleAuthorOnly,
    );
  }

  final selected =
      lifecycle == BeaconLifecycle.open &&
      coord == BeaconCoordinationStatus.neutral;

  return BeaconStatusMenuRow(
    id: BeaconStatusMenuRowId.open,
    action: BeaconStatusMenuAction.setCoordinationNeutral,
    isSelected: selected,
    isEnabled: input.canSetCoordination,
    disabledReason: input.canSetCoordination
        ? BeaconStatusMenuDisabledReason.none
        : BeaconStatusMenuDisabledReason.lifecycleAuthorOnly,
  );
}

BeaconStatusMenuRow _coordinationRow({
  required BeaconStatusMenuRowId id,
  required BeaconStatusMenuAction action,
  required BeaconStatusMenuInput input,
  required BeaconCoordinationStatus status,
}) {
  final lifecycle = input.beacon.lifecycle;
  final allowsCoordination =
      lifecycle == BeaconLifecycle.open ||
      lifecycle == BeaconLifecycle.reviewOpen;
  final selected =
      allowsCoordination && input.beacon.coordinationStatus == status;

  if (lifecycle == BeaconLifecycle.draft) {
    return BeaconStatusMenuRow(
      id: id,
      action: action,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.publishFirst,
    );
  }

  if (!allowsCoordination) {
    return BeaconStatusMenuRow(
      id: id,
      action: action,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.terminalState,
    );
  }

  return BeaconStatusMenuRow(
    id: id,
    action: action,
    isSelected: selected,
    isEnabled: input.canSetCoordination,
    disabledReason: input.canSetCoordination
        ? BeaconStatusMenuDisabledReason.none
        : BeaconStatusMenuDisabledReason.lifecycleAuthorOnly,
  );
}

BeaconStatusMenuRow _moreHelpRow(BeaconStatusMenuInput input) =>
    // When lifecycle is reviewOpen, selecting this row reverts to Open (server).
    _coordinationRow(
      id: BeaconStatusMenuRowId.moreHelp,
      action: BeaconStatusMenuAction.setCoordinationMoreHelp,
      input: input,
      status: BeaconCoordinationStatus.moreOrDifferentHelpNeeded,
    );

BeaconStatusMenuRow _enoughHelpRow(BeaconStatusMenuInput input) =>
    _coordinationRow(
      id: BeaconStatusMenuRowId.enoughHelp,
      action: BeaconStatusMenuAction.setCoordinationEnoughHelp,
      input: input,
      status: BeaconCoordinationStatus.enoughHelpOffered,
    );

bool _closeBlocked(BeaconStatusMenuInput input) =>
    input.closureReadiness == BeaconClosureReadiness.blocked &&
    !input.allowForceCloseWhenBlocked;

BeaconStatusMenuRow _wrappingUpRow(BeaconStatusMenuInput input) {
  final lifecycle = input.beacon.lifecycle;
  final selected = lifecycle == BeaconLifecycle.reviewOpen;
  final review = input.reviewWindow;

  if (lifecycle == BeaconLifecycle.draft) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.wrappingUp,
      action: BeaconStatusMenuAction.startWrappingUp,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.publishFirst,
    );
  }

  if (lifecycle == BeaconLifecycle.reviewOpen) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.wrappingUp,
      action: BeaconStatusMenuAction.none,
      isSelected: true,
      isEnabled: false,
      secondaryAction: BeaconStatusMenuAction.extendReview,
      isSecondaryEnabled:
          input.canManageLifecycle && (review?.canExtend ?? false),
    );
  }

  if (!input.canManageLifecycle) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.wrappingUp,
      action: BeaconStatusMenuAction.startWrappingUp,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.lifecycleAuthorOnly,
    );
  }

  if (_closeBlocked(input)) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.wrappingUp,
      action: BeaconStatusMenuAction.startWrappingUp,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.blocked,
    );
  }

  if (!input.hasCommitters) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.wrappingUp,
      action: BeaconStatusMenuAction.startWrappingUp,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.noCommitters,
    );
  }

  return BeaconStatusMenuRow(
    id: BeaconStatusMenuRowId.wrappingUp,
    action: BeaconStatusMenuAction.startWrappingUp,
    isSelected: false,
    isEnabled: true,
  );
}

BeaconStatusMenuRow _closedRow(BeaconStatusMenuInput input) {
  final lifecycle = input.beacon.lifecycle;
  final review = input.reviewWindow;

  if (lifecycle == BeaconLifecycle.draft) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.closed,
      action: BeaconStatusMenuAction.closeDirect,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.publishFirst,
    );
  }

  if (lifecycle == BeaconLifecycle.reviewOpen) {
    final canClose = input.canManageLifecycle && (review?.canCloseNow ?? false);
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.closed,
      action: BeaconStatusMenuAction.closeNow,
      isSelected: false,
      isEnabled: canClose,
      disabledReason: canClose
          ? BeaconStatusMenuDisabledReason.none
          : (input.canManageLifecycle
                ? BeaconStatusMenuDisabledReason.waitingForReviewers
                : BeaconStatusMenuDisabledReason.lifecycleAuthorOnly),
    );
  }

  if (!input.canManageLifecycle) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.closed,
      action: BeaconStatusMenuAction.closeDirect,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.lifecycleAuthorOnly,
    );
  }

  if (_closeBlocked(input)) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.closed,
      action: BeaconStatusMenuAction.closeDirect,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.blocked,
    );
  }

  if (input.hasCommitters) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.closed,
      action: BeaconStatusMenuAction.closeDirect,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.finishReviewFirst,
    );
  }

  if (input.closureReadiness == BeaconClosureReadiness.premature) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.closed,
      action: BeaconStatusMenuAction.closeDirect,
      isSelected: false,
      isEnabled: true,
      disabledReason: BeaconStatusMenuDisabledReason.notReadyToClose,
    );
  }

  return BeaconStatusMenuRow(
    id: BeaconStatusMenuRowId.closed,
    action: BeaconStatusMenuAction.closeDirect,
    isSelected: false,
    isEnabled: true,
  );
}

BeaconStatusMenuRow _cancelledRow(BeaconStatusMenuInput input) {
  final lifecycle = input.beacon.lifecycle;

  if (lifecycle == BeaconLifecycle.reviewOpen) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.cancelled,
      action: BeaconStatusMenuAction.cancel,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.cancelWrappingUp,
    );
  }

  if (lifecycle == BeaconLifecycle.draft) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.cancelled,
      action: BeaconStatusMenuAction.cancel,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.publishFirst,
    );
  }

  if (!input.canManageLifecycle) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.cancelled,
      action: BeaconStatusMenuAction.cancel,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.lifecycleAuthorOnly,
    );
  }

  if (input.beacon.helpOfferCount > 0) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.cancelled,
      action: BeaconStatusMenuAction.cancel,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.cancelHasOffers,
    );
  }

  return BeaconStatusMenuRow(
    id: BeaconStatusMenuRowId.cancelled,
    action: BeaconStatusMenuAction.cancel,
    isSelected: false,
    isEnabled: true,
  );
}
