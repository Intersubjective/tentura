/// Thrown when Tentura V2 GraphQL returns HTTP error code **1303**
/// (duplicate fact pin for the same room message).
class BeaconFactAlreadyPinnedRemoteException implements Exception {
  const BeaconFactAlreadyPinnedRemoteException({required this.factCardId});

  final String factCardId;

  /// Server code: 1300 + enum index 3.
  static const codeNumber = 1303;

  @override
  String toString() => 'BeaconFactAlreadyPinnedRemoteException($factCardId)';
}
