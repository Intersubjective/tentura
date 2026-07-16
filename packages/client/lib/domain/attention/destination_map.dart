import 'package:tentura/consts.dart';

import 'entity/attention_receipt.dart';

/// Resolves typed server targets while retaining [AttentionReceipt.actionUrl]
/// for old/unknown receipt classes.
Uri attentionDestination(AttentionReceipt receipt) {
  final target = receipt.targetEntityId;
  final beaconId = receipt.beaconId;
  if (target == null || target.isEmpty) return Uri.parse(receipt.actionUrl);
  return switch (receipt.destinationKind) {
    'beacon' => Uri(path: '$kPathBeaconView/$target'),
    'beacon_people_offer' when beaconId != null => Uri(
      path: '$kPathBeaconView/$beaconId',
      queryParameters: {kQueryBeaconViewTab: 'people'},
    ),
    'beacon_room' when beaconId != null => Uri(
      path: '$kPathBeaconView/$beaconId',
      queryParameters: {kQueryBeaconViewTab: 'room'},
    ),
    'beacon_room_message' when beaconId != null => Uri(
      path: '$kPathBeaconView/$beaconId',
      queryParameters: {kQueryBeaconViewTab: 'room', kQueryMessageId: target},
    ),
    'review' => Uri(path: '$kPathReviewContributions/$target'),
    'profile' => Uri(path: '$kPathProfileView/$target'),
    _ => Uri.parse(receipt.actionUrl),
  };
}
