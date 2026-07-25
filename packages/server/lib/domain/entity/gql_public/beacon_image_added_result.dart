import 'package:meta/meta.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';

/// Result of the legacy `beaconAddImage` bridge (GraphQL
/// `v2_BeaconImageAdded`). `id` stays the beacon id for compatibility with
/// old `{ id }` selections; `imageId` is the exact created image id.
@immutable
class BeaconImageAddedResult {
  const BeaconImageAddedResult({
    required this.imageId,
    required this.beacon,
  });

  final String imageId;
  final BeaconEntity beacon;

  String get id => beacon.id;
}
