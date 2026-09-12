/// Stable opaque node identity for scene topology and layout.
typedef GraphNodeId = String;

/// Stable opaque edge identity; parallel edges require distinct IDs.
typedef GraphEdgeId = String;

/// Rejects empty graph identifiers.
void assertNonEmptyGraphId(String id, String name) {
  if (id.isEmpty) {
    throw ArgumentError.value(id, name, 'must not be empty');
  }
}
