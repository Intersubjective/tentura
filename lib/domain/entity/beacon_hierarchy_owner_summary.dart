/// Owner identity safe for hierarchy cards and composer previews.
class BeaconHierarchyOwnerSummary {
  const BeaconHierarchyOwnerSummary({
    required this.id,
    required this.displayName,
    this.avatarImageId,
  });

  final String id;
  final String displayName;
  final String? avatarImageId;
}
