/// Ephemeral post-invite navigation intent (beacon → Inbox tab).
class PostJoinDestination {
  const PostJoinDestination({
    this.beaconId,
    this.beaconTitle,
    this.inviterName,
    this.showSnackbar = true,
  });

  final String? beaconId;
  final String? beaconTitle;
  final String? inviterName;
  final bool showSnackbar;

  bool get hasBeacon => beaconId != null && beaconId!.isNotEmpty;
}
