import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';

import 'package:tentura/domain/entity/beacon.dart';

/// Client-side hierarchy reads and child draft creation orchestration.
abstract interface class BeaconHierarchyPort {
  Future<BeaconHierarchyCapabilities> capabilities(String beaconId);

  Future<BeaconHierarchyPage> listChildren({
    required String parentBeaconId,
    required BeaconHierarchyChildGroup group,
    int first = 20,
    String? after,
  });

  Future<BeaconParentReference> parentReference(String beaconId);

  Future<BeaconPromotionSource> promotionSource({
    required String parentBeaconId,
    required String sourceMessageId,
  });

  Future<BeaconChildCreateDraftResult> createChildDraft({
    required BeaconCreationContext creationContext,
    required String clientCommandId,
    required Beacon draftFields,
  });
}

/// Result of starting a child draft through the hierarchy port.
class BeaconChildCreateDraftResult {
  const BeaconChildCreateDraftResult({
    required this.outcome,
    required this.beacon,
  });

  final BeaconChildCommandOutcome outcome;
  final Beacon beacon;
}
