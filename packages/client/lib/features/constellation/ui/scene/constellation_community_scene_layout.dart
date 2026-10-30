import 'package:collection/collection.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

import '../../domain/entity/constellation_field.dart';
import '../../domain/layout/constellation_communities.dart';
import '../../domain/layout/constellation_transition_stages.dart';

/// Screen-local geometry only. Normal seats are kept separately so overview
/// coordinates never become the normal layout's inertia on a later pass.
class ConstellationCommunitySceneLayouts {
  _CommunityLayoutData? _data;

  /// Staging of the bulk move between normal and overview geometry, keyed by
  /// graph node id: one stage per community, Requests following their author.
  /// One map for the cubit's lifetime so a mounted graph view reads updates
  /// without a rebuild.
  final Map<String, LayoutTransitionStage> transitionStages = {};

  /// Close-detail seats, including magnets, for an atomic recenter jump.
  Map<String, ScenePoint>? get normalPositions {
    final data = _data;
    return data != null && data.normalReady ? data.normalPositions : null;
  }

  void clear() {
    _data = null;
    transitionStages.clear();
  }

  void _stage(
    ConstellationCommunityLayout layout,
    Map<String, String> followers,
  ) {
    final staged = stageConstellationTransition(
      communities: layout.communities,
    );
    transitionStages
      ..clear()
      ..addAll({
        for (final e in staged.entries)
          'fp:${e.key}': LayoutTransitionStage(
            delay: e.value.delay,
            duration: e.value.duration,
          ),
      });
    for (final e in followers.entries) {
      final stage = transitionStages[e.value];
      if (stage != null) transitionStages[e.key] = stage;
    }
  }

  SceneLayoutAlgorithm select({
    required SceneLayoutAlgorithm normal,
    required ConstellationField field,
    required String egoId,
    required Map<String, ConstellationAnchorPosition> anchors,
    required Map<String, ScenePoint> initialPositions,
    required bool overview,
  }) {
    final old = _data;
    if (old == null && !overview) return normal;
    final edges = [
      for (final e in field.edges) (src: e.src, dst: e.dst, tier: e.tier),
    ];
    final sameEdges =
        old != null &&
        const ListEquality<ConstellationEdgeRef>().equals(old.edges, edges);
    final sameAnchors =
        old != null &&
        const MapEquality<String, ConstellationAnchorPosition>().equals(
          old.anchors,
          anchors,
        );
    if (old == null || old.base != normal || !sameEdges || !sameAnchors) {
      _data = _CommunityLayoutData(
        base: normal,
        egoId: egoId,
        edges: edges,
        anchors: Map.of(anchors),
        normalPositions: old?.normalPositions ?? initialPositions,
        normalReady: old == null,
        previous: old?.communities ?? old?.previous,
        communities: sameEdges && sameAnchors ? old.communities : null,
        followers: {
          for (final r in field.requests) 'fr:${r.id}': 'fp:${r.authorId}',
          for (final p in field.posts) 'fr:${p.id}': 'fp:${p.authorId}',
        },
        onCommunities: (layout, followers) => _stage(layout, followers),
      );
    }
    return overview ? _data!.overviewAlgorithm : _data!.normalAlgorithm;
  }
}

class _CommunityLayoutData {
  _CommunityLayoutData({
    required this.base,
    required this.egoId,
    required this.edges,
    required this.anchors,
    required this.normalPositions,
    required this.normalReady,
    required this.previous,
    required this.communities,
    required this.followers,
    required this.onCommunities,
  });

  final SceneLayoutAlgorithm base;
  final String egoId;
  final List<ConstellationEdgeRef> edges;
  final Map<String, ConstellationAnchorPosition> anchors;
  final Map<String, String> followers;
  final void Function(
    ConstellationCommunityLayout layout,
    Map<String, String> followers,
  )
  onCommunities;
  final ConstellationCommunityLayout? previous;
  ConstellationCommunityLayout? communities;
  Map<String, ScenePoint> normalPositions;
  bool normalReady;

  late final normalAlgorithm = _CommunitySceneLayout(this, overview: false);
  late final overviewAlgorithm = _CommunitySceneLayout(this, overview: true);

  Stream<GraphLayoutFrame> normalFrames(GraphLayoutRequest request) async* {
    if (normalReady &&
        const SetEquality<String>().equals(
          normalPositions.keys.toSet(),
          request.nodeIds.toSet(),
        )) {
      yield GraphLayoutFrame(
        ticket: request.ticket,
        sequence: 0,
        positions: normalPositions,
        isTerminal: true,
      );
      return;
    }
    final prior = request.previous;
    final clean = GraphLayoutRequest(
      ticket: request.ticket,
      canvasSize: request.canvasSize,
      nodesById: request.nodesById,
      edgesById: request.edgesById,
      previous: prior == null
          ? null
          : SceneLayout(
              ticket: prior.ticket,
              revision: prior.revision,
              positions: normalPositions,
            ),
    );
    await for (final frame in base.layout(clean)) {
      if (frame.isTerminal) {
        normalPositions = frame.positions;
        normalReady = true;
      }
      yield frame;
    }
  }

  Map<String, ScenePoint> overviewPositions() {
    final people = {
      for (final e in normalPositions.entries)
        if (e.key.startsWith('fp:') && e.key != 'fp:$egoId')
          e.key.substring(3): (x: e.value.x, y: e.value.y),
    };
    final ego = normalPositions['fp:$egoId']!;
    var layout = communities;
    if (layout == null ||
        !const SetEquality<String>().equals(
          layout.positions.keys.toSet(),
          people.keys.toSet(),
        )) {
      layout = computeConstellationCommunities(
        ego: (x: ego.x, y: ego.y),
        fieldPositions: people,
        trustEdges: edges,
        pinnedPositions: {
          for (final id in people.keys)
            if (anchors.containsKey(id)) id: people[id]!,
        },
        seed: 42,
        previous: communities ?? previous,
      );
      communities = layout;
      onCommunities(layout, followers);
    }
    final positions = {
      ...normalPositions,
      for (final e in layout.positions.entries)
        'fp:${e.key}': ScenePoint(x: e.value.x, y: e.value.y),
    };
    for (final e in followers.entries) {
      final at = normalPositions[e.key];
      final author = normalPositions[e.value];
      final moved = positions[e.value];
      if (at != null &&
          author != null &&
          moved != null &&
          !anchors.containsKey(e.key.substring(3))) {
        positions[e.key] = ScenePoint(
          x: at.x + moved.x - author.x,
          y: at.y + moved.y - author.y,
        );
      }
    }
    return positions;
  }
}

class _CommunitySceneLayout implements SceneLayoutAlgorithm {
  const _CommunitySceneLayout(this.data, {required this.overview});
  final _CommunityLayoutData data;
  final bool overview;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    await for (final frame in data.normalFrames(request)) {
      if (!overview) {
        yield frame;
      } else if (frame.isTerminal) {
        final positions = data.overviewPositions();
        yield GraphLayoutFrame(
          ticket: request.ticket,
          sequence: frame.sequence,
          positions: {
            for (final id in request.nodeIds) id: ?positions[id],
          },
          isTerminal: true,
        );
      }
    }
  }
}
