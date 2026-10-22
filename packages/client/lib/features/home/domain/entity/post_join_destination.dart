/// Ephemeral post-invite navigation intent (beacon → Inbox tab).
class PostJoinDestination {
  const PostJoinDestination({
    this.beaconId,
    this.beaconTitle,
    this.inviterName,
    this.showSnackbar = true,
    this.isPost = false,
  });

  final String? beaconId;
  final String? beaconTitle;
  final String? inviterName;
  final bool showSnackbar;

  /// The shared beacon is a Post (#501): copy says "post".
  final bool isPost;

  bool get hasBeacon => beaconId != null && beaconId!.isNotEmpty;
}
