import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

/// B077 — when the author accepted the viewer's help offer on an active
/// helper card, the moment it happened; null when there is nothing to show.
///
/// "Accepted" is the author's acknowledging response that comes with the
/// room invitation (`CoordinationResponseType.allowsInviteToRoom`), the same
/// response the author's Accept writes.
DateTime? myWorkOfferAcceptedAt(MyWorkCardViewModel vm) {
  if (vm.kind != MyWorkCardKind.helpOfferedActive) return null;
  if (vm.authorResponseType?.allowsInviteToRoom != true) return null;
  return vm.authorCoordinationUpdatedAt ??
      vm.helpOfferRowUpdatedAt ??
      vm.beacon.updatedAt;
}
