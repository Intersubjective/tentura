import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_grid_clusters.dart';
import '../utils/constellation_presentation_frame.dart';

/// Labels and ego bundles share the same screen-space partition on every
/// camera/drag frame. Dragging a label reports the cluster and the drag in
/// screen points through [onClusterDragged]; this layer writes nothing itself.
///
/// A label is not part of any dot's semantics rect: each label registers in
/// [clusterLabels], and [ConstellationClusterLabelSemantics] exposes its tap
/// targets beneath the map's dots (#640).
class ConstellationOverviewLayer extends StatelessWidget {
  const ConstellationOverviewLayer({
    required this.frame,
    required this.viewerId,
    this.peopleTags,
    this.onClusterDragged,
    this.clusterLabels,
    super.key,
  });

  final ConstellationPresentationFrame frame;
  final String viewerId;
  final PeopleTagsCase? peopleTags;

  /// A label was dragged and let go: the people it counts and how far (screen
  /// points) it was dragged.
  final void Function(List<String> personIds, Offset screenDelta)?
  onClusterDragged;

  /// Where the labels are laid out, for [ConstellationClusterLabelSemantics].
  final ConstellationClusterLabels? clusterLabels;

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
    stream: peopleTags?.changes,
    builder: (context, _) {
      final tags = peopleTags?.tags ?? const [];
      final positions = {
        for (final entry in frame.bodies.entries)
          if (entry.key.startsWith('fp:') && entry.key != 'fp:$viewerId')
            entry.key.substring(3): (
              x: entry.value.center.dx,
              y: entry.value.center.dy,
            ),
      };
      final clusters = computeConstellationGridClusters(
        screenPositions: positions,
        ownTagIdsInOrder: [for (final tag in tags) tag.id],
        ownTagIdsByPerson: {
          for (final id in positions.keys)
            id: peopleTags?.tagsOfPerson(id) ?? const {},
        },
      );
      final tt = context.tt;
      final scheme = Theme.of(context).colorScheme;
      final l10n = L10n.of(context)!;
      final ego = frame.bodies['fp:$viewerId']?.center;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          if (ego != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _BundlePainter(
                    ego: ego,
                    clusters: clusters,
                    color: tt.graphEdgePath,
                    widthPerPerson: tt.tightGap / kConstellationGridCellSize,
                  ),
                ),
              ),
            ),
          for (final cluster in clusters)
            Positioned(
              left: cluster.centre.x,
              top: cluster.centre.y,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: _ClusterLabelTargets(
                  centre: Offset(cluster.centre.x, cluster.centre.y),
                  dots: {
                    for (final MapEntry(:key, :value) in positions.entries)
                      key: Offset(value.x, value.y),
                  },
                  labels: clusterLabels,
                  child: _DraggableClusterLabel(
                    onDragged: (delta) =>
                        onClusterDragged?.call(cluster.personIds, delta),
                    child: Text(
                      switch (cluster.dominantTagId) {
                        final id? =>
                          '${tags.firstWhere((tag) => tag.id == id).name} · ${cluster.personIds.length}',
                        null => l10n.constellationClusterPeople(
                          cluster.personIds.length,
                        ),
                      },
                      style: TenturaText.labelSmall(scheme.onSurface),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// The cluster labels laid out on the overview map, with the map's dots.
final class ConstellationClusterLabels extends ChangeNotifier {
  final _labels = <_RenderClusterLabelTargets>{};

  void _changed() => notifyListeners();
}

/// [child], a label centred on [centre], registered in [labels] while it is
/// laid out. [centre] and [dots] are in the overview layer's coordinates.
class _ClusterLabelTargets extends SingleChildRenderObjectWidget {
  const _ClusterLabelTargets({
    required this.centre,
    required this.dots,
    required this.labels,
    required super.child,
  });

  final Offset centre;
  final Map<String, Offset> dots;
  final ConstellationClusterLabels? labels;

  @override
  _RenderClusterLabelTargets createRenderObject(BuildContext context) =>
      _RenderClusterLabelTargets(centre: centre, dots: dots, labels: labels);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderClusterLabelTargets renderObject,
  ) {
    renderObject
      ..updateLabels(labels)
      ..centre = centre
      ..dots = dots;
  }
}

class _RenderClusterLabelTargets extends RenderProxyBox {
  _RenderClusterLabelTargets({
    required this.centre,
    required this.dots,
    required this._labels,
  });

  Offset centre;
  Map<String, Offset> dots;

  ConstellationClusterLabels? _labels;
  void updateLabels(ConstellationClusterLabels? value) {
    if (value == _labels) {
      return;
    }
    if (attached) {
      _leave();
    }
    _labels = value;
    if (attached) {
      _join();
    }
  }

  /// [dots] in this label's own coordinates.
  Map<String, Offset> get localDots {
    final shift = size.center(Offset.zero) - centre;
    return {
      for (final MapEntry(:key, :value) in dots.entries) key: value + shift,
    };
  }

  void _join() => _labels
    ?.._labels.add(this)
    .._changed();

  void _leave() => _labels
    ?.._labels.remove(this)
    .._changed();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _join();
  }

  @override
  void detach() {
    _leave();
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    // The label moves with the camera: its targets move with it.
    _labels?._changed();
  }
}

/// The tap targets of the labels in [labels], one per nearest person:
/// each covers a run of the label where, across its full height,
/// that person's dot is the nearest of them, and a tap on it reports that
/// person through [onPersonTapped].
///
/// Placed beneath the map, so a dot's own semantics rect wins where it and
/// a label overlap: a tap on a dot always selects that dot (#640). Paints
/// nothing and takes no pointer events.
class ConstellationClusterLabelSemantics extends LeafRenderObjectWidget {
  const ConstellationClusterLabelSemantics({
    required this.labels,
    required this.onPersonTapped,
    super.key,
  });

  final ConstellationClusterLabels labels;
  final ValueChanged<String> onPersonTapped;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderConstellationClusterLabelSemantics(
        labels: labels,
        onPersonTapped: onPersonTapped,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConstellationClusterLabelSemantics renderObject,
  ) {
    renderObject
      ..updateLabels(labels)
      ..onPersonTapped = onPersonTapped;
  }
}

class RenderConstellationClusterLabelSemantics extends RenderBox {
  RenderConstellationClusterLabelSemantics({
    required this._labels,
    required this.onPersonTapped,
  });

  ConstellationClusterLabels _labels;
  void updateLabels(ConstellationClusterLabels value) {
    if (value == _labels) {
      return;
    }
    if (attached) {
      _labels.removeListener(markNeedsSemanticsUpdate);
      value.addListener(markNeedsSemanticsUpdate);
    }
    _labels = value;
    markNeedsSemanticsUpdate();
  }

  ValueChanged<String> onPersonTapped;

  final _targets = <SemanticsNode>[];

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _labels.addListener(markNeedsSemanticsUpdate);
  }

  @override
  void detach() {
    _labels.removeListener(markNeedsSemanticsUpdate);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..explicitChildNodes = true;
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    final rects = <(String, Rect)>[];
    for (final label in _labels._labels) {
      if (!label.attached || !label.hasSize) {
        continue;
      }
      final toHere = label.getTransformTo(this);
      final box = MatrixUtils.transformRect(toHere, Offset.zero & label.size);
      final dots = {
        for (final MapEntry(:key, :value) in label.localDots.entries)
          key: MatrixUtils.transformPoint(toHere, value),
      };
      for (final (id, from, to) in _nearestDotRuns(
        dots,
        box: box,
      )) {
        rects.add((id, Rect.fromLTRB(from, box.top, to, box.bottom)));
      }
    }
    while (_targets.length < rects.length) {
      _targets.add(SemanticsNode());
    }
    _targets.length = rects.length;
    for (var i = 0; i < rects.length; i++) {
      final (id, rect) = rects[i];
      _targets[i]
        ..rect = rect
        ..updateWith(
          config: SemanticsConfiguration()
            ..isButton = true
            ..onTap = () => onPersonTapped(id),
        );
    }
    node.updateWith(
      config: config,
      childrenInInversePaintOrder: _targets.toList(),
    );
  }
}

/// For each of [dots], the run of x in [box] where its dot is nearest
/// across the full height, as (id, start, end), left to right. Gaps reach
/// the map as pointer events, which resolve the nearest dot at the tap's y.
/// A dot nearest nowhere has no run. On a tie the earlier dot wins.
List<(String, double, double)> _nearestDotRuns(
  Map<String, Offset> dots, {
  required Rect box,
}) {
  // Squared distance to dot i is x² − 2·xᵢ·x + cᵢ, so dot i beats dot j
  // where 2·(xⱼ − xᵢ)·x ≤ cⱼ − cᵢ: a half-line of x.
  final entries = dots.entries.toList();
  double c(Offset p, double y) => p.dx * p.dx + (p.dy - y) * (p.dy - y);
  final runs = <(String, double, double)>[];
  for (var i = 0; i < entries.length; i++) {
    final pi = entries[i].value;
    var start = box.left;
    var end = box.right;
    for (var j = 0; j < entries.length && start < end; j++) {
      if (j == i) {
        continue;
      }
      final pj = entries[j].value;
      final slope = 2 * (pj.dx - pi.dx);
      // Use the edge of the label nearest the neighbour: the rect must
      // stay on this dot's side of the bisector at both top and bottom.
      final y = pj.dy > pi.dy ? box.bottom : box.top;
      final gap = c(pj, y) - c(pi, y);
      if (slope > 0) {
        end = math.min(end, gap / slope);
      } else if (slope < 0) {
        start = math.max(start, gap / slope);
      } else if (gap < 0 || (gap == 0 && j < i)) {
        end = start;
      }
    }
    if (start < end) {
      runs.add((entries[i].key, start, end));
    }
  }
  return runs..sort((a, b) => a.$2.compareTo(b.$2));
}

/// Adds up one pan on [child] and reports the whole drag when it ends.
class _DraggableClusterLabel extends StatefulWidget {
  const _DraggableClusterLabel({required this.onDragged, required this.child});

  final ValueChanged<Offset> onDragged;
  final Widget child;

  @override
  State<_DraggableClusterLabel> createState() => _DraggableClusterLabelState();
}

class _DraggableClusterLabelState extends State<_DraggableClusterLabel> {
  Offset _delta = Offset.zero;

  @override
  Widget build(BuildContext context) => GestureDetector(
    // Keep the cluster's pan recognizer in the hit path while allowing taps
    // to reach person dots beneath the label.
    behavior: HitTestBehavior.translucent,
    // The distance before the pan is recognised counts as dragged too.
    dragStartBehavior: DragStartBehavior.down,
    onPanStart: (_) => _delta = Offset.zero,
    onPanUpdate: (details) => _delta += details.delta,
    onPanEnd: (_) => widget.onDragged(_delta),
    child: IgnorePointer(child: widget.child),
  );
}

class _BundlePainter extends CustomPainter {
  const _BundlePainter({
    required this.ego,
    required this.clusters,
    required this.color,
    required this.widthPerPerson,
  });

  final Offset ego;
  final List<ConstellationGridCluster> clusters;
  final Color color;
  final double widthPerPerson;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    for (final cluster in clusters) {
      paint.strokeWidth = widthPerPerson * cluster.personIds.length;
      canvas.drawLine(ego, Offset(cluster.centre.x, cluster.centre.y), paint);
    }
  }

  @override
  bool shouldRepaint(_BundlePainter oldDelegate) =>
      ego != oldDelegate.ego ||
      clusters != oldDelegate.clusters ||
      color != oldDelegate.color ||
      widthPerPerson != oldDelegate.widthPerPerson;
}
