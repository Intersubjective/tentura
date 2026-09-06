import 'package:tentura_server/consts/beacon_room_consts.dart';

/// Facts about a candidate promotion source message.
///
/// Client-side twin for Task 11: mirror this shape in
/// `packages/client/lib/domain/policy/beacon_promotion_eligibility_policy.dart`.
final class BeaconPromotionSourceFacts {
  const BeaconPromotionSourceFacts({
    required this.messageId,
    required this.beaconId,
    required this.authorId,
    required this.body,
    this.threadItemId,
    this.systemMessageKind,
    this.systemPayload,
    this.semanticMarker,
    this.linkedItemId,
    this.linkedPollingId,
    this.linkedEventKind,
    this.linkedNextMoveId,
    this.linkedFactCardId,
  });

  final String messageId;
  final String beaconId;
  final String? authorId;
  final String body;
  final String? threadItemId;
  final int? systemMessageKind;
  final Map<String, Object?>? systemPayload;
  final int? semanticMarker;
  final String? linkedItemId;
  final String? linkedPollingId;
  final int? linkedEventKind;
  final String? linkedNextMoveId;
  final String? linkedFactCardId;
}

/// Pure promotion-source eligibility (§3.4.9).
abstract final class BeaconPromotionEligibilityPolicy {
  BeaconPromotionEligibilityPolicy._();

  static bool isEligible(BeaconPromotionSourceFacts facts) {
    if (facts.authorId == null || facts.authorId!.isEmpty) {
      return false;
    }
    if (facts.threadItemId != null && facts.threadItemId!.isNotEmpty) {
      return false;
    }
    if (facts.systemMessageKind != null) {
      return false;
    }
    if (facts.systemPayload != null && facts.systemPayload!.isNotEmpty) {
      return false;
    }
    if (facts.semanticMarker != null) {
      if (facts.semanticMarker == BeaconRoomSemanticMarker.blocker ||
          facts.semanticMarker == BeaconRoomSemanticMarker.needInfo ||
          facts.semanticMarker == BeaconRoomSemanticMarker.done) {
        return false;
      }
      return false;
    }
    if (facts.linkedItemId != null && facts.linkedItemId!.isNotEmpty) {
      return false;
    }
    if (facts.linkedPollingId != null && facts.linkedPollingId!.isNotEmpty) {
      return false;
    }
    if (facts.linkedEventKind != null) {
      return false;
    }
    if (facts.linkedNextMoveId != null && facts.linkedNextMoveId!.isNotEmpty) {
      return false;
    }
    if (facts.linkedFactCardId != null && facts.linkedFactCardId!.isNotEmpty) {
      return false;
    }
    return true;
  }
}
