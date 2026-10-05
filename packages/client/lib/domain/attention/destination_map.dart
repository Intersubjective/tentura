import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

import 'attention_event_classification.dart';
import 'entity/attention_receipt.dart';

/// Resolves typed server targets while retaining [AttentionReceipt.actionUrl]
/// for old/unknown receipt classes.
Uri attentionDestination(AttentionReceipt receipt) {
  final target = receipt.targetEntityId;
  final beaconId = receipt.beaconId;
  if (target == null || target.isEmpty) return Uri.parse(receipt.actionUrl);
  if (receipt.destinationKind == 'beacon' && _isPlanReceipt(receipt)) {
    final step = receipt.coordinationItemId?.trim();
    return Uri(
      path: '$kPathBeaconView/$target',
      queryParameters: {
        kQueryBeaconViewTab: kBeaconViewTabPlan,
        if (step != null && step.isNotEmpty) kQueryPlanStepId: step,
      },
    );
  }
  return switch (receipt.destinationKind) {
    'beacon' => Uri(path: '$kPathBeaconView/$target'),
    'beacon_people_offer' when beaconId != null => Uri(
      path: '$kPathBeaconView/$beaconId',
      queryParameters: {kQueryBeaconViewTab: 'people'},
    ),
    'beacon_room' when beaconId != null => Uri(
      path: '$kPathBeaconView/$beaconId',
      queryParameters: {
        kQueryBeaconViewTab: kBeaconViewTabThreads,
        kQueryThreadId: RequestThread.generalId,
      },
    ),
    'beacon_room_message' when beaconId != null => Uri(
      path: '$kPathBeaconView/$beaconId',
      queryParameters: {
        kQueryBeaconViewTab: kBeaconViewTabThreads,
        kQueryMessageId: target,
      },
    ),
    'profile' => Uri(path: '$kPathProfileView/$target'),
    _ => Uri.parse(receipt.actionUrl),
  };
}

/// Request plan events (#220) open the Plan tab, on the step when there is
/// one.
bool _isPlanReceipt(AttentionReceipt receipt) {
  final type = attentionEventTypeOf(receipt.presentationPayloadJson);
  if (type != null) return type.startsWith('plan');
  return receipt.presentationKey?.startsWith('plan_') ?? false;
}
