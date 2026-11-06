import 'package:meta/meta.dart';

import 'package:tentura/features/forward/domain/entity/forward_graph.dart';

/// Session-local overlay: full forward tree on the Field (#774, 31ve.6).
@immutable
final class ConstellationForwardTreeOverlay {
  const ConstellationForwardTreeOverlay({
    required this.beaconId,
    this.helpOffererFocusId,
    this.graph,
    this.loading = false,
    this.error,
    this.arrangeAsTree = false,
    this.replayGeneration = 0,
    this.replayVisibleCount,
    this.replaying = false,
    this.reduceMotion = false,
    this.savedPersonPositions,
    this.savedRequestPositions,
    this.savedBeaconPositions,
  });

  final String beaconId;

  /// When set, helpBranch edges follow paths to this help offerer.
  final String? helpOffererFocusId;

  final ForwardGraph? graph;
  final bool loading;
  final Object? error;

  /// Radial tree layout around the author.
  final bool arrangeAsTree;

  /// Bumped to restart replay.
  final int replayGeneration;

  /// When non-null and `< graph.edges.length`, only that many edges (by createdAt).
  final int? replayVisibleCount;

  final bool replaying;

  final bool reduceMotion;

  final Map<String, ({double x, double y})>? savedPersonPositions;
  final Map<String, ({double x, double y})>? savedRequestPositions;
  final Map<String, ({double x, double y})>? savedBeaconPositions;

  bool get hasGraph => graph != null && graph!.edges.isNotEmpty;

  ConstellationForwardTreeOverlay copyWith({
    String? beaconId,
    String? helpOffererFocusId,
    ForwardGraph? graph,
    bool? loading,
    Object? error,
    bool clearError = false,
    bool? arrangeAsTree,
    int? replayGeneration,
    int? replayVisibleCount,
    bool clearReplayVisibleCount = false,
    bool? replaying,
    bool? reduceMotion,
    Map<String, ({double x, double y})>? savedPersonPositions,
    Map<String, ({double x, double y})>? savedRequestPositions,
    Map<String, ({double x, double y})>? savedBeaconPositions,
    bool clearSavedPositions = false,
  }) => ConstellationForwardTreeOverlay(
    beaconId: beaconId ?? this.beaconId,
    helpOffererFocusId: helpOffererFocusId ?? this.helpOffererFocusId,
    graph: graph ?? this.graph,
    loading: loading ?? this.loading,
    error: clearError ? null : error ?? this.error,
    arrangeAsTree: arrangeAsTree ?? this.arrangeAsTree,
    replayGeneration: replayGeneration ?? this.replayGeneration,
    replayVisibleCount: clearReplayVisibleCount
        ? null
        : (replayVisibleCount ?? this.replayVisibleCount),
    replaying: replaying ?? this.replaying,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    savedPersonPositions: clearSavedPositions
        ? null
        : (savedPersonPositions ?? this.savedPersonPositions),
    savedRequestPositions: clearSavedPositions
        ? null
        : (savedRequestPositions ?? this.savedRequestPositions),
    savedBeaconPositions: clearSavedPositions
        ? null
        : (savedBeaconPositions ?? this.savedBeaconPositions),
  );
}
