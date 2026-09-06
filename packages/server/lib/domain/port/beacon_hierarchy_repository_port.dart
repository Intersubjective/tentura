import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

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
}
