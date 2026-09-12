import 'package:force_directed_graphview/src/scene/graph_ids.dart';

/// Deterministic seed for layout RNG from an opaque node id (not [Object.hashCode]
/// of a render payload or [NodeBase] instance).
int graphNodeIdLayoutSeed(GraphNodeId id) => Object.hash('graph.layout.seed', id);
