/// Author operations that end a Post's lifetime or bring its deadline closer.
abstract interface class PostLifecyclePort {
  /// Shortens the deadline; the server rejects an extension.
  Future<void> postShorten(String beaconId, {required DateTime expiresAt});

  /// Closes the Post immediately.
  Future<void> postClose(String beaconId);
}
