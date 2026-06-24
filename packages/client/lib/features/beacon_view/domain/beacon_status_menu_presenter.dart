import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_status_menu.dart';

String beaconStatusMenuRowLabel(L10n l10n, BeaconStatusMenuRowId id) =>
    switch (id) {
      BeaconStatusMenuRowId.draft => l10n.beaconStatusRowDraft,
      BeaconStatusMenuRowId.open => l10n.beaconStatusRowOpen,
      BeaconStatusMenuRowId.moreHelp => l10n.coordinationMoreHelpNeeded,
      BeaconStatusMenuRowId.enoughHelp => l10n.coordinationEnoughHelp,
      BeaconStatusMenuRowId.wrappingUp => l10n.beaconStatusRowWrappingUp,
      BeaconStatusMenuRowId.closed => l10n.beaconStatusRowClosed,
      BeaconStatusMenuRowId.cancelled => l10n.beaconStatusRowCancelled,
    };

String beaconStatusMenuOpenRowLabel(L10n l10n, Beacon beacon) {
  return switch (beacon.status) {
    BeaconStatus.draft => l10n.beaconStatusRowPublish,
    BeaconStatus.reviewOpen => l10n.beaconReviewReopenAction,
    BeaconStatus.open when beacon.helpOfferCount > 0 =>
      l10n.beaconPhaseCoordinating,
    _ => l10n.beaconStatusRowOpen,
  };
}

String beaconStatusMenuDisabledReasonLabel(
  L10n l10n,
  BeaconStatusMenuDisabledReason reason,
) =>
    switch (reason) {
      BeaconStatusMenuDisabledReason.none => '',
      BeaconStatusMenuDisabledReason.publishFirst =>
        l10n.beaconStatusHintPublishFirst,
      BeaconStatusMenuDisabledReason.finishReviewFirst =>
        l10n.beaconStatusHintFinishReviewFirst,
      BeaconStatusMenuDisabledReason.noCommitters =>
        l10n.beaconStatusHintNoCommitters,
      BeaconStatusMenuDisabledReason.cancelHasOffers =>
        l10n.beaconStatusHintCancelHasOffers,
      BeaconStatusMenuDisabledReason.cancelWrappingUp =>
        l10n.beaconStatusHintCancelWrappingUp,
      BeaconStatusMenuDisabledReason.blocked => l10n.beaconStatusHintBlocked,
      BeaconStatusMenuDisabledReason.notReadyToClose =>
        l10n.beaconStatusHintNotReadyToClose,
      BeaconStatusMenuDisabledReason.waitingForReviewers =>
        l10n.beaconReviewCloseNowBlocked,
      BeaconStatusMenuDisabledReason.lifecycleAuthorOnly =>
        l10n.beaconStatusHintAuthorOnly,
      BeaconStatusMenuDisabledReason.terminalState => '',
    };

/// Overview / NOW detail situation state line (replaces publicStatus).
String beaconSituationStateLine(L10n l10n, Beacon beacon) {
  return switch (beacon.status) {
    BeaconStatus.draft => l10n.beaconStatusRowDraft,
    BeaconStatus.reviewOpen => l10n.beaconStatusRowWrappingUp,
    BeaconStatus.closed => l10n.beaconStatusRowClosed,
    BeaconStatus.cancelled => l10n.beaconStatusRowCancelled,
    BeaconStatus.deleted => l10n.beaconHudBeaconUnavailable,
    BeaconStatus.needsMoreHelp => l10n.coordinationMoreHelpNeeded,
    BeaconStatus.enoughHelp => l10n.coordinationEnoughHelp,
    BeaconStatus.open =>
      beacon.helpOfferCount > 0
          ? l10n.beaconPhaseCoordinating
          : l10n.beaconStatusRowOpen,
  };
}
