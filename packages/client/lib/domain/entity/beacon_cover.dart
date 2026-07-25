import 'package:tentura/domain/capability/capability_tag.dart';

import 'image_entity.dart';

/// Resolved visual identity of a request: exactly one of photo, symbol, neutral.
sealed class BeaconIdentity {
  const BeaconIdentity();
}

final class BeaconIdentityPhoto extends BeaconIdentity {
  const BeaconIdentityPhoto(this.image);

  final ImageEntity image;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BeaconIdentityPhoto && image == other.image;

  @override
  int get hashCode => image.hashCode;
}

final class BeaconIdentitySymbol extends BeaconIdentity {
  const BeaconIdentitySymbol(this.tag);

  final CapabilityTag tag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BeaconIdentitySymbol && tag == other.tag;

  @override
  int get hashCode => tag.hashCode;
}

final class BeaconIdentityNeutral extends BeaconIdentity {
  const BeaconIdentityNeutral();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BeaconIdentityNeutral;

  @override
  int get hashCode => (BeaconIdentityNeutral).hashCode;
}
