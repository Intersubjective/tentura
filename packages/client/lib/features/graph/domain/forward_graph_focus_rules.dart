/// Viewer role in help-offerer forward path graph mode.
enum ForwardsGraphViewerRole {
  /// Viewer is the beacon author (root of the chain).
  author,

  /// Viewer is the focused help offerer; focus rotates onto the author.
  self,

  /// Viewer is neither author nor help offerer but appears on the chain.
  involvedOther,
}

/// Resolves how the signed-in viewer relates to the help-offerer path graph.
ForwardsGraphViewerRole resolveHelpOffererViewerRole({
  required String viewerId,
  required String authorId,
  required String helpOffererId,
}) {
  if (viewerId == authorId) {
    return ForwardsGraphViewerRole.author;
  }
  if (viewerId == helpOffererId) {
    return ForwardsGraphViewerRole.self;
  }
  return ForwardsGraphViewerRole.involvedOther;
}

/// Focus node for help-offerer-path mode (help offerer, or author when viewer
/// is the help offerer so the chain reads in reverse).
String deriveHelpOffererGraphFocus({
  required bool viewerIsHelpOfferer,
  required String authorId,
  required String helpOffererId,
}) => viewerIsHelpOfferer ? authorId : helpOffererId;

/// MeritRank rating arcs are shown on graph nodes except the viewer's ego node.
bool graphNodeShowsMeritRankRating({
  required String nodeId,
  required String viewerId,
}) =>
    nodeId.isNotEmpty && nodeId != viewerId;
