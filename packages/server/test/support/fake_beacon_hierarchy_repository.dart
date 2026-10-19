import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/entity/beacon_structural_record.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';

/// No-op hierarchy port for unit tests that do not exercise hierarchy reads.
class FakeBeaconHierarchyRepository implements BeaconHierarchyRepositoryPort {
  int lockMutationScopeCalls = 0;

  @override
  Future<void> lockMutationScope() async {
    lockMutationScopeCalls++;
  }

  @override
  Future<BeaconHierarchyCapabilities> loadCapabilities({
    required String parentBeaconId,
    required String viewerId,
  }) => throw UnimplementedError();

  @override
  Future<BeaconHierarchyPage> listChildren({
    required String parentBeaconId,
    required String viewerId,
    required BeaconHierarchyChildGroup group,
    required int first,
    String? after,
  }) => throw UnimplementedError();

  @override
  Future<BeaconHierarchySummary?> loadChildPreview({
    required String beaconId,
    required String viewerId,
  }) => throw UnimplementedError();

  /// Guarded parent links by child id; a child not listed has no parent
  /// (`BeaconParentReference.none`). Tests that exercise the Requests list
  /// batch (#487) seed this map.
  final Map<String, BeaconParentReference> parentReferences = {};

  /// Child ids passed to the per-id [loadParentReference], in call order.
  /// The Requests list batch must not use it (#487 review, PR #610: one
  /// read per Request was an N+1 on the inbox).
  final List<String> parentReferenceCalls = [];

  @override
  Future<BeaconParentReference> loadParentReference({
    required String childBeaconId,
    required String viewerId,
  }) async {
    parentReferenceCalls.add(childBeaconId);
    return parentReferences[childBeaconId] ?? BeaconParentReference.none;
  }

  /// Each call to the batched [loadParentReferences]: the child ids asked
  /// for and the viewer.
  final List<({Set<String> childBeaconIds, String viewerId})>
  parentReferencesBatchCalls = [];

  /// Batched guarded parent links: only children whose parent is
  /// [BeaconParentReferenceState.available] to the viewer are in the map.
  @override
  Future<Map<String, BeaconParentReference>> loadParentReferences({
    required Set<String> childBeaconIds,
    required String viewerId,
  }) async {
    parentReferencesBatchCalls.add((
      childBeaconIds: Set<String>.of(childBeaconIds),
      viewerId: viewerId,
    ));
    return {
      for (final id in childBeaconIds)
        if (parentReferences[id] case final ref?
            when ref.state == BeaconParentReferenceState.available &&
                ref.beaconId != null)
          id: ref,
    };
  }

  @override
  Future<BeaconPromotionSource> loadPromotionSource({
    required String parentBeaconId,
    required String sourceMessageId,
    required String viewerId,
  }) => throw UnimplementedError();

  BeaconStatus statusOverride = BeaconStatus.open;

  @override
  Future<BeaconStatus?> loadBeaconStatus(String beaconId) async =>
      statusOverride;

  @override
  Future<String?> loadImmediateParentBeaconId(String childBeaconId) =>
      throw UnimplementedError();

  @override
  Future<BeaconStructuralRecord?> loadStructuralRecord(String beaconId) async =>
      null;
}

/// Runs [action] directly — for unit tests that need [MutatingUnitOfWorkPort].
class PassThroughMutatingUnitOfWork extends Fake
    implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) => action();
}
