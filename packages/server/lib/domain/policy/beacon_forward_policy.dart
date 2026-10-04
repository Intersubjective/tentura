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
}
