import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
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
  }) =>
      throw UnimplementedError();

  @override
  Future<BeaconHierarchyPage> listChildren({
    required String parentBeaconId,
    required String viewerId,
    required BeaconHierarchyChildGroup group,
    required int first,
    String? after,
  }) =>
      throw UnimplementedError();

  @override
  Future<BeaconParentReference> loadParentReference({
    required String childBeaconId,
    required String viewerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<BeaconPromotionSource> loadPromotionSource({
    required String parentBeaconId,
    required String sourceMessageId,
    required String viewerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<BeaconStatus?> loadBeaconStatus(String beaconId) =>
      throw UnimplementedError();

  @override
  Future<String?> loadImmediateParentBeaconId(String childBeaconId) =>
      throw UnimplementedError();
}

/// Runs [action] directly — for unit tests that need [MutatingUnitOfWorkPort].
class PassThroughMutatingUnitOfWork extends Fake
    implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) =>
      action();
}
