import 'package:tentura/features/forward/domain/entity/forward_recipient_offer_status.dart';

/// Per-recipient state on a forward edge, merged onto graph nodes in forwards mode.
///
/// Aligned with `ConstellationForwardTreeRecipientMarker` ranking in the Field
/// forward-tree overlay — keep semantics in sync when server fields change.

enum ForwardsRecipientMarker {
  helped,
  offered,
  cantHelp,
  opened,
  notOpened,
}

/// Merges markers from several incoming edges onto one recipient node (lowest rank wins).
ForwardsRecipientMarker? mergeForwardsRecipientMarkers(
  ForwardsRecipientMarker? a,
  ForwardsRecipientMarker? b,
) {
  if (a == null) return b;
  if (b == null) return a;
  int rank(ForwardsRecipientMarker m) => switch (m) {
    ForwardsRecipientMarker.helped => 0,
    ForwardsRecipientMarker.offered => 1,
    ForwardsRecipientMarker.cantHelp => 2,
    ForwardsRecipientMarker.opened => 3,
    ForwardsRecipientMarker.notOpened => 4,
  };
  return rank(a) <= rank(b) ? a : b;
}

/// Single-letter cue under avatars and in the forwards legend (V/D/K/O/R).
String? forwardsRecipientMarkerAbbreviation(ForwardsRecipientMarker? m) => switch (m) {
      ForwardsRecipientMarker.helped => 'V',
      ForwardsRecipientMarker.cantHelp => 'D',
      ForwardsRecipientMarker.notOpened => 'K',
      ForwardsRecipientMarker.offered => 'O',
      ForwardsRecipientMarker.opened => 'R',
      null => null,
    };

ForwardsRecipientMarker? forwardsMarkerFromEdge({
  required ForwardRecipientOfferStatus? offerStatus,
  bool? declinedInvite,
  DateTime? readAt,
  bool? forwardedOn,
}) {
  // Mirrors constellation_scene_controller markerFor (Field forward tree).
  if (offerStatus == ForwardRecipientOfferStatus.accepted) {
    return ForwardsRecipientMarker.helped;
  }
  if (offerStatus == ForwardRecipientOfferStatus.offered) {
    return ForwardsRecipientMarker.offered;
  }
  if (declinedInvite == true) {
    return ForwardsRecipientMarker.cantHelp;
  }
  if (readAt != null) {
    return ForwardsRecipientMarker.opened;
  }
  if (forwardedOn == false) {
    return ForwardsRecipientMarker.notOpened;
  }
  return null;
}
