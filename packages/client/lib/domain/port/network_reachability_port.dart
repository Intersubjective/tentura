/// Whether the app can currently reach the network (#513): fed by request
/// outcomes and the browser's online/offline signal, read by the offline
/// banner.
abstract interface class NetworkReachabilityPort {
  bool get isOnline;

  /// Emits the new value each time [isOnline] changes.
  Stream<bool> get onlineChanges;
}
