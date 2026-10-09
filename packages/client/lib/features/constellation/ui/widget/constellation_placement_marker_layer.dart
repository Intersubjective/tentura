import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../domain/placement_overlay.dart';
import '../bloc/constellation_cubit.dart';
import 'constellation_placement_marker.dart';

/// Places a [ConstellationPlacementMarker] above each node whose placement
/// write is slow or did not reach the server, following the camera.
class ConstellationPlacementMarkerLayer extends StatefulWidget {
  const ConstellationPlacementMarkerLayer({required this.cubit, super.key});

  final ConstellationCubit cubit;

  @override
  State<ConstellationPlacementMarkerLayer> createState() =>
      _ConstellationPlacementMarkerLayerState();
}

class _ConstellationPlacementMarkerLayerState
    extends State<ConstellationPlacementMarkerLayer> {
  late final StreamSubscription<Object?> _subscription;
  Map<ConstellationAnchorTarget, PlacementCue> _cues = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _subscription = widget.cubit.placementChanges.listen((_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }

  /// A write earns its "Saving…" cue by staying in flight, not by an event.
  void _refresh() {
    final (:cues, :nextChange) = widget.cubit.placementCues;
    _timer?.cancel();
    _timer = nextChange == null
        ? null
        : Timer(nextChange + const Duration(milliseconds: 1), _refresh);
    if (mapEquals(cues, _cues)) return;
    if (mounted) setState(() => _cues = cues);
  }

  @override
  Widget build(BuildContext context) {
    if (_cues.isEmpty) return const SizedBox.shrink();
    final controller = widget.cubit.graphController;
    final gap = context.tt.tightGap;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.cameraRevision]),
      builder: (context, _) {
        final snapshot = controller.renderSnapshot;
        final scale = controller.cameraScale;
        final markers = <Widget>[];
        for (final MapEntry(key: target, value: cue) in _cues.entries) {
          final graphId = _sceneNodeId(target);
          final node = snapshot.topology.nodesById[graphId];
          final point = snapshot.resolvePosition(graphId);
          if (node == null || point == null) continue;
          final centre = controller.sceneToViewportLocal(
            Offset(point.x, point.y),
          );
          markers.add(
            Positioned.fill(
              key: ValueKey('constellation.placement.$graphId'),
              child: CustomSingleChildLayout(
                delegate: _MarkerLayout(
                  Offset(
                    centre.dx,
                    centre.dy - node.size.width * scale / 2 - gap,
                  ),
                ),
                child: ConstellationPlacementMarker(
                  status: switch (cue) {
                    PlacementCue.saving =>
                      ConstellationPlacementMarkerStatus.saving,
                    PlacementCue.notSaved =>
                      ConstellationPlacementMarkerStatus.notSaved,
                  },
                  onRetry: () => widget.cubit.retryPlacement(target),
                  onDiscard: () => widget.cubit.discardPlacement(target),
                ),
              ),
            ),
          );
        }
        return Stack(children: markers);
      },
    );
  }
}

/// The scene node a placement target is drawn as.
String _sceneNodeId(ConstellationAnchorTarget target) => switch (target.kind) {
  ConstellationAnchorTargetKind.person => 'fp:${target.id}',
  ConstellationAnchorTargetKind.beacon => 'fr:${target.id}',
};

/// Sits the marker's bottom centre on [anchor], then pulls it back into the
/// viewport so a node scrolled out of sight still has a reachable marker.
class _MarkerLayout extends SingleChildLayoutDelegate {
  const _MarkerLayout(this.anchor);

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (anchor.dx - childSize.width / 2).clamp(
      0,
      max(0, size.width - childSize.width),
    ),
    (anchor.dy - childSize.height).clamp(
      0,
      max(0, size.height - childSize.height),
    ),
  );

  @override
  bool shouldRelayout(_MarkerLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}
