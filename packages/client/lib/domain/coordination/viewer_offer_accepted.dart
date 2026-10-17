import 'package:tentura_root/domain/entity/beacon_access.dart';

/// B077 — the one rule for "the author accepted my help offer", shared by the
/// Requests tab (My Work helper card) and the request's People tab.
///
/// The offer counts as accepted while the viewer is admitted to the request's
/// room ([BeaconAccessReason.admitted] in the viewer's access reasons). That
/// is the same fact #508 calls an "accepted helper", and it covers the cases
/// the author's response alone gets wrong: a `useful` response written
/// without the room invitation, and a helper removed from the room later
/// while the response stays `useful`.
bool isViewerOfferAccepted({
  required bool hasActiveOffer,
  required int viewerAccessReasons,
}) =>
    hasActiveOffer &&
    viewerAccessReasons & BeaconAccessReason.admitted.bit != 0;
