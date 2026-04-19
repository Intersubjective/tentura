import 'node_details.dart';

/// One directed edge for the graph view.
///
/// `node` is an optional payload describing the destination node (the source
/// node is resolved from a separate index in the cubit). When `node` is
/// `null`, the cubit lazy-fetches the destination using the id prefix
/// (`U` -> profile, `B` -> beacon).
typedef EdgeDirected = ({
  String src,
  String dst,
  double weight,
  NodeDetails? node,
});
