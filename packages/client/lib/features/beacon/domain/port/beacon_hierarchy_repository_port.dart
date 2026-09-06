import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

/// Result of an authorized child create/publish command (plan §3.5).
///
/// `beaconId` is the newly created (or previously replayed) child's ID; it
/// is only ever populated when the outcome is currently readable by the
/// caller — never disclosed for an unauthorized `alreadyPromoted` conflict.
class BeaconChildCreateOutcome {
  const BeaconChildCreateOutcome({
    required this.outcome,
    this.beaconId,
  });

  final BeaconChildCommandOutcome outcome;
  final String? beaconId;
}

/// Client-side V2 hierarchy transport (plan §3.5 API surface). Pure domain
/// values in, pure domain values out — no raw GraphQL/Ferry types cross this
/// boundary, and no unrestricted raw parent/child relationship query exists
/// beyond the five specified operations.
abstract class BeaconHierarchyRepositoryPort {
  Future<BeaconHierarchyCapabilities> fetchCapabilities({
    required String beaconId,
  });

  Future<BeaconHierarchyPage> fetchChildren({
    required String parentBeaconId,
    required BeaconHierarchyChildGroup group,
    int first = 20,
    String? after,
  });

  Future<BeaconParentReference> fetchParentReference({
    required String beaconId,
  });

  Future<BeaconPromotionSource> fetchPromotionSource({
    required String parentBeaconId,
    required String sourceMessageId,
  });

  Future<BeaconChildCreateOutcome> createChild({
    required String parentBeaconId,
    String? sourceMessageId,
    required String clientCommandId,
    required String title,
    String? description,
    String? context,
    Coordinates? coordinates,
    DateTime? startAt,
    DateTime? endAt,
    String? tags,
    String? needs,
    String? primaryNeedSlug,
    String? addressLabel,
    bool draft = false,
  });
}
