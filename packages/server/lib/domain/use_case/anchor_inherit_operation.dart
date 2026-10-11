import 'dart:math' as math;

import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';

import 'package:tentura_server/domain/port/bud_anchor_sweep_port.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';

/// Gives a viewer a child-Request anchor next to their anchor on the Post the
/// Request budded from (Arch §8.1, plan C8).
///
/// Insert-if-absent: the op carries `ifRevision = 0`, so a child anchor the
/// viewer already placed (or removed) is never overwritten. The op id
/// `bud:<child>:<viewer>` makes a repeated call replay from the op log.
///
/// It calls [ConstellationAnchorRepositoryPort.applyBatch], which runs its
/// own viewer-scoped transaction through the constellation scheduler, so it
/// must never be called inside another mutating transaction.
@Singleton(order: 1)
final class AnchorInheritOperation {
  const AnchorInheritOperation(this._anchors, this._sweep);

  /// Where an open Post's child lands relative to the Post, in units.
  static const offsetUnits = 0.6;

  final ConstellationAnchorRepositoryPort _anchors;
  final BudAnchorSweepPort _sweep;

  static String opId({
    required String childBeaconId,
    required String viewerId,
  }) => 'bud:$childBeaconId:$viewerId';

  /// The child position for a Post anchor at [post]: the same spot when the
  /// Post is closed (the child replaces it), else a fixed offset, kept inside
  /// the coordinate space.
  static ConstellationAnchorPosition childPosition(BudPostPlacement post) {
    if (post.postClosed) return post.position;
    double shift(double v) {
      final moved = v + offsetUnits;
      return moved <= kConstellationCoordinateMaxUnits
          ? moved
          : math.max(kConstellationCoordinateMinUnits, v - offsetUnits);
    }

    return ConstellationAnchorPosition(
      xUnits: shift(post.position.xUnits),
      yUnits: shift(post.position.yUnits),
      coordinateSpaceVersion: post.position.coordinateSpaceVersion,
    );
  }

  /// Anchors [childBeaconId] for [viewerId] next to their anchor on [postId].
  /// Returns false when the viewer has no live Post anchor.
  Future<bool> inherit({
    required String childBeaconId,
    required String postId,
    required String viewerId,
  }) async {
    final placement = await _sweep.postPlacement(
      viewerId: viewerId,
      postId: postId,
    );
    if (placement == null) return false;
    await _anchors.applyBatch(
      viewerId: viewerId,
      ops: [
        AnchorApplyOp(
          clientOpId: opId(childBeaconId: childBeaconId, viewerId: viewerId),
          kind: AnchorOpKind.upsert,
          target: ConstellationAnchorTarget.beacon(childBeaconId),
          position: childPosition(placement),
          ifRevision: ConstellationAnchorRevision.zero,
        ),
      ],
    );
    return true;
  }
}
