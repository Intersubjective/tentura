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
  });

  final BeaconParentReferenceState state;
  final String? beaconId;
  final String? title;

  static const none = BeaconParentReference(state: BeaconParentReferenceState.none);

  static const unavailable = BeaconParentReference(
    state: BeaconParentReferenceState.unavailable,
  );
}
