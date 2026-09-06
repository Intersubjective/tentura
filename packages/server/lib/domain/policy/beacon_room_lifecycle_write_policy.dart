import 'package:tentura_root/domain/entity/beacon_status.dart';

/// Rejects ordinary user writes on terminal request lifecycles.
///
/// Internal system notices (hierarchy lifecycle, child-created) bypass this
/// policy at the repository layer — they never route through these guards.
abstract final class BeaconRoomLifecycleWritePolicy {
  BeaconRoomLifecycleWritePolicy._();

  static bool blocksOrdinaryUserWrites(BeaconStatus status) =>
      status == BeaconStatus.closed ||
      status == BeaconStatus.cancelled ||
      status == BeaconStatus.deleted;
}
