import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

part 'placement_outbox.freezed.dart';

@freezed
sealed class PlacementOp with _$PlacementOp {
  const factory PlacementOp.upsert({
    required String clientOpId,
    required String clusterId,
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
    ConstellationAnchorRevision? ifRevision,
  }) = PlacementUpsert;

  const factory PlacementOp.delete({
    required String clientOpId,
    required String clusterId,
    required ConstellationAnchorTarget target,
    ConstellationAnchorRevision? ifRevision,
  }) = PlacementDelete;
}

enum PlacementSlotStatus { queued, inFlight, commitUnknown, rejected }

@freezed
abstract class PlacementSlot with _$PlacementSlot {
  const factory PlacementSlot({
    required PlacementOp op,
    required PlacementSlotStatus status,
    @Default(0) int attempts,
    String? reasonCode,
    ConstellationAnchor? preOpConfirmed,
    // Dispatch time; absent until the slot is sent.
    DateTime? inFlightSince,
  }) = _PlacementSlot;
}

@freezed
abstract class PlacementTargetState with _$PlacementTargetState {
  const factory PlacementTargetState({
    PlacementSlot? inFlight,
    PlacementSlot? latestPending,
  }) = _PlacementTargetState;
}

@freezed
abstract class PlacementOutboxState with _$PlacementOutboxState {
  const factory PlacementOutboxState({
    required Map<ConstellationAnchorTarget, PlacementTargetState> targets,
    required bool hasUserPlacements,
    required int generation,
  }) = _PlacementOutboxState;
}
