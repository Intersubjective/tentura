import 'package:tentura/domain/coordination/viewer_offer_accepted.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

/// B077 — when the author accepted the viewer's help offer on an active
/// helper card, the moment it happened; null when there is nothing to show.
///
/// "Accepted" is [isViewerOfferAccepted]: the viewer is admitted to the
/// request's room — the same rule the People tab uses.
DateTime? myWorkOfferAcceptedAt(MyWorkCardViewModel vm) {
  if (vm.kind != MyWorkCardKind.helpOfferedActive) return null;
  if (!isViewerOfferAccepted(
    hasActiveOffer: true,
    viewerAccessReasons: vm.beacon.accessReasons,
  )) {
    return null;
  }
  return vm.authorCoordinationUpdatedAt ??
      vm.helpOfferRowUpdatedAt ??
      vm.beacon.updatedAt;
}
