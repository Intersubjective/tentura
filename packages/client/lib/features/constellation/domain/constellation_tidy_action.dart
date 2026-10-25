import 'constellation_tidy_offset_layer.dart';
import 'constellation_tidy_up.dart';
import 'layout/layout_geometry.dart';
import 'use_case/constellation_arrangement_history.dart';

/// What a «Tidy up» that moved people reports.
typedef ConstellationTidyOutcome = ({
  int movedCount,
  Map<String, LPoint> moves,
});

/// Runs «Tidy up», keeps the result in the offset layer and records it as one
/// undo entry.
class ConstellationTidyAction {
  ConstellationTidyAction({required this.layer, required this.history});

  final ConstellationTidyOffsetLayer layer;
  final ConstellationArrangementHistory history;

  /// Null when nobody had to move.
  ConstellationTidyOutcome? tidy({
    required LPoint ego,
    required List<ConstellationTidyNode> nodes,
    Set<String>? selection,
    LRect? visibleRect,
  }) {
    final result = constellationTidyUp(
      ego: ego,
      nodes: nodes,
      selection: selection,
      visibleRect: visibleRect,
    );
    if (result.moves.isEmpty) return null;
    final before = layer.offsets;
    layer.recordMoves(
      from: {for (final n in nodes) n.id: n.position},
      to: result.moves,
    );
    history.record(TidyOffsetEntry(before: before, after: layer.offsets));
    return (movedCount: result.movedCount, moves: result.moves);
  }
}
