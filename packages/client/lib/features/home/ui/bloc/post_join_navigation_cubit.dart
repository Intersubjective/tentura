import 'package:injectable/injectable.dart';

import '../../domain/entity/post_join_destination.dart';

/// Holds consume-once post-invite navigation intent until [HomeScreen] mounts.
@singleton
class PostJoinNavigationCubit {
  PostJoinDestination? _pending;

  bool get hasPending => _pending?.hasBeacon ?? false;

  void set(PostJoinDestination destination) {
    _pending = destination;
  }

  void setFromBeaconInvite({
    required String beaconId,
    required String beaconTitle,
    String inviterName = '',
    bool showSnackbar = true,
  }) {
    _pending = PostJoinDestination(
      beaconId: beaconId,
      beaconTitle: beaconTitle,
      inviterName: inviterName,
      showSnackbar: showSnackbar,
    );
  }

  PostJoinDestination? takeDestination() {
    final dest = _pending;
    _pending = null;
    return dest;
  }
}
