import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/ui/l10n/l10n.dart';

String coordinationStatusLabel(L10n l10n, BeaconCoordinationStatus s) =>
    switch (s) {
      BeaconCoordinationStatus.noCommitmentsYet => l10n.coordinationNoCommitments,
      BeaconCoordinationStatus.commitmentsWaitingForReview =>
        l10n.coordinationWaitingForReview,
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded =>
        l10n.coordinationMoreHelpNeeded,
      BeaconCoordinationStatus.enoughHelpCommitted => l10n.coordinationEnoughHelp,
    };

String? coordinationResponseLabel(L10n l10n, CoordinationResponseType? r) {
  if (r == null) return null;
  return switch (r) {
    CoordinationResponseType.useful => l10n.coordinationUseful,
    CoordinationResponseType.overlapping => l10n.coordinationOverlapping,
    CoordinationResponseType.needDifferentSkill =>
      l10n.coordinationNeedDifferentSkill,
    CoordinationResponseType.needCoordination =>
      l10n.coordinationNeedCoordination,
    CoordinationResponseType.notSuitable => l10n.coordinationNotSuitable,
  };
}

String? uncommitReasonLabel(L10n l10n, String? wireKey) {
  if (wireKey == null || wireKey.isEmpty) return null;
  return switch (wireKey) {
    'cannot_do_it' => l10n.uncommitCantDoIt,
    'timing' => l10n.uncommitTimingChanged,
    'wrong_fit' => l10n.uncommitWrongFit,
    'someone_else' => l10n.uncommitSomeoneElseTookOver,
    'other' => l10n.uncommitOther,
    _ => wireKey,
  };
}

String? helpTypeLabel(L10n l10n, String? wireKey) {
  if (wireKey == null || wireKey.isEmpty) return null;
  return switch (wireKey) {
    'money' => l10n.helpTypeMoney,
    'time' => l10n.helpTypeTime,
    'skill' => l10n.helpTypeSkill,
    'verification' => l10n.helpTypeVerification,
    'contact' => l10n.helpTypeContact,
    'transport' => l10n.helpTypeTransport,
    'other' => l10n.helpTypeOther,
    _ => wireKey,
  };
}
