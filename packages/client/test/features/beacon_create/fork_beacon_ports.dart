import 'dart:async';

import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';

import 'fake_beacon_ports.dart';

/// One recorded lineage fork.
class ForkCall {
  const ForkCall({
    required this.sourceId,
    required this.copyPlan,
    required this.planStepTimes,
  });

  final String sourceId;
  final bool copyPlan;
  final List<PlanStepTime> planStepTimes;
}

/// Write port with a published source Request and a server-side lineage
/// fork, shaped like `BeaconRepository.fork`: the server copies the source
/// verbatim (same title) and re-uploads its images under new ids.
class ForkingBeaconWritePort extends FakeBeaconWritePort {
  ForkingBeaconWritePort({required this.source});

  final Beacon source;
  final forkCalls = <ForkCall>[];

  /// When set, [fork] waits until this completes (overlapping first saves).
  Completer<void>? forkHold;

  @override
  Future<Beacon> fetchBeaconById(String id) async =>
      id == source.id ? source : beacon;

  @override
  Future<Beacon> fork(
    String sourceId, {
    bool copyPlan = false,
    List<PlanStepTime> planStepTimes = const [],
  }) async {
    forkCalls.add(
      ForkCall(
        sourceId: sourceId,
        copyPlan: copyPlan,
        planStepTimes: planStepTimes,
      ),
    );
    final hold = forkHold;
    if (hold != null) await hold.future;
    final copied = source.images.isEmpty
        ? const <ImageEntity>[]
        : const [ImageEntity(id: 'copy-img', authorId: 'author-1')];
    return beacon = source.copyWith(
      id: 'fork-1',
      status: BeaconStatus.draft,
      lineageParentBeaconId: source.id,
      images: copied,
      coverImageId: copied.isEmpty ? null : copied.first.id,
    );
  }
}
