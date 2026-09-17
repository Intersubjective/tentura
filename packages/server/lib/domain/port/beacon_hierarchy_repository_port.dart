import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_structural_record.dart';

/// Read-side hierarchy projections and structural facts.
abstract class BeaconHierarchyRepositoryPort {
  Future<void> lockMutationScope();

  Future<BeaconHierarchyCapabilities> loadCapabilities({
    required String parentBeaconId,
    required String viewerId,
  });

  Future<BeaconHierarchyPage> listChildren({
    required String parentBeaconId,
    required String viewerId,
    required BeaconHierarchyChildGroup group,
    required int first,
    String? after,
  });

  /// Single-child authorized preview using the same projection as [listChildren].
  /// Returns null when the viewer cannot read content or the row is a tombstone.
  Future<BeaconHierarchySummary?> loadChildPreview({
    required String beaconId,
    required String viewerId,
  });

  Future<BeaconParentReference> loadParentReference({
    required String childBeaconId,
    required String viewerId,
  });

  Future<BeaconPromotionSource> loadPromotionSource({
    required String parentBeaconId,
    required String sourceMessageId,
    required String viewerId,
  });

  Future<BeaconStatus?> loadBeaconStatus(String beaconId);

  Future<String?> loadImmediateParentBeaconId(String childBeaconId);

  /// Structural facts for deleted rows whose owner FK was nulled by erasure.
  Future<BeaconStructuralRecord?> loadStructuralRecord(String beaconId);
}
