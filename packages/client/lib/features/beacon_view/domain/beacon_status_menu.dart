import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

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
    this.canCloseNow,
    this.maxExtensions = kMaxBeaconReviewExtensions,
  });

  static const int kMaxBeaconReviewExtensions = 2;

  final int reviewedCount;
  final int totalCount;
  final bool windowComplete;
  final int extensionsUsed;
  final bool? canCloseNow;
  final int maxExtensions;

  bool get canExtend => extensionsUsed < maxExtensions;

  bool get serverCanCloseNow => canCloseNow == true;
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
  final lifecycle = input.beacon.status;

  if (lifecycle == BeaconStatus.closed ||
      lifecycle == BeaconStatus.cancelled ||
      lifecycle == BeaconStatus.deleted) {
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

List<BeaconStatusMenuRow> _terminalRows(BeaconStatus status) {
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
      selected: status == BeaconStatus.closed,
    ),
    row(
      BeaconStatusMenuRowId.cancelled,
      selected: status == BeaconStatus.cancelled,
    ),
  ];
}

BeaconStatusMenuRow _draftRow(BeaconStatusMenuInput input) {
  final selected = input.beacon.status == BeaconStatus.draft;
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
  final lifecycle = input.beacon.status;
  final coord = input.beacon.status;

  if (lifecycle == BeaconStatus.draft) {
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

  if (lifecycle == BeaconStatus.reviewOpen) {
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
      lifecycle == BeaconStatus.open &&
      coord == BeaconStatus.open;

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
  required BeaconStatus status,
}) {
  final lifecycle = input.beacon.status;
  final allowsCoordination = lifecycle.isOpenFamily ||
      lifecycle == BeaconStatus.reviewOpen;
  final selected =
      allowsCoordination && input.beacon.status == status;

  if (lifecycle == BeaconStatus.draft) {
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
      status: BeaconStatus.needsMoreHelp,
    );

BeaconStatusMenuRow _enoughHelpRow(BeaconStatusMenuInput input) =>
    _coordinationRow(
      id: BeaconStatusMenuRowId.enoughHelp,
      action: BeaconStatusMenuAction.setCoordinationEnoughHelp,
      input: input,
      status: BeaconStatus.enoughHelp,
    );

bool _closeBlocked(BeaconStatusMenuInput input) =>
    input.closureReadiness == BeaconClosureReadiness.blocked &&
    !input.allowForceCloseWhenBlocked;

BeaconStatusMenuRow _wrappingUpRow(BeaconStatusMenuInput input) {
  final lifecycle = input.beacon.status;
  final selected = lifecycle == BeaconStatus.reviewOpen;
  final review = input.reviewWindow;

  if (lifecycle == BeaconStatus.draft) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.wrappingUp,
      action: BeaconStatusMenuAction.startWrappingUp,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.publishFirst,
    );
  }

  if (lifecycle == BeaconStatus.reviewOpen) {
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
  final lifecycle = input.beacon.status;
  final review = input.reviewWindow;

  if (lifecycle == BeaconStatus.draft) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.closed,
      action: BeaconStatusMenuAction.closeDirect,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.publishFirst,
    );
  }

  if (lifecycle == BeaconStatus.reviewOpen) {
    final canClose = input.canManageLifecycle && (review?.serverCanCloseNow ?? false);
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
  final lifecycle = input.beacon.status;

  if (lifecycle == BeaconStatus.reviewOpen) {
    return BeaconStatusMenuRow(
      id: BeaconStatusMenuRowId.cancelled,
      action: BeaconStatusMenuAction.cancel,
      isSelected: false,
      isEnabled: false,
      disabledReason: BeaconStatusMenuDisabledReason.cancelWrappingUp,
    );
  }

  if (lifecycle == BeaconStatus.draft) {
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

  if (input.hasCommitters) {
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
