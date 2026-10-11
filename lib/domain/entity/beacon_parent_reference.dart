/// Whether an immediate parent link may be shown on a readable child.
enum BeaconParentReferenceState {
  none,
  available,
  unavailable,
}

/// Guarded parent link for child detail headers.
class BeaconParentReference {
  const BeaconParentReference({
    required this.state,
    this.beaconId,
    this.title,
    this.isPost = false,
  });

  final BeaconParentReferenceState state;
  final String? beaconId;
  final String? title;

  /// The parent is a Post (a budded Request). Set only with
  /// [BeaconParentReferenceState.available]: an unreadable parent does not
  /// reveal its kind.
  final bool isPost;

  static const none = BeaconParentReference(
    state: BeaconParentReferenceState.none,
  );

  static const unavailable = BeaconParentReference(
    state: BeaconParentReferenceState.unavailable,
  );
}
