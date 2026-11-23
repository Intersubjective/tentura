import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';

/// Who may create forward edges (direct forwards and invite-borne forwards).
abstract final class BeaconForwardPolicy {
  BeaconForwardPolicy._();

  static bool canForward({
    required BeaconEntity beacon,
    required String senderId,
  }) =>
      beacon.allowsForward &&
      (beacon.forwardPolicy == BeaconForwardPolicyValue.open ||
          senderId == beacon.author.id);

  static Future<bool> canForwardRequestInvite({
    required BeaconEntity beacon,
    required String issuerId,
    required Future<bool> Function() issuerCanReadContent,
  }) async {
    final expiresAt = beacon.expiresAt;
    return canForward(beacon: beacon, senderId: issuerId) &&
        (expiresAt == null || expiresAt.isAfter(DateTime.timestamp())) &&
        await issuerCanReadContent();
  }
}
