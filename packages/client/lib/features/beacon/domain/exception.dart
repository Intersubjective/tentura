sealed class BeaconException implements Exception {
  const BeaconException([this.message]);

  final Object? message;

  @override
  String toString() => message?.toString() ?? super.toString();
}

final class BeaconFetchException extends BeaconException {
  const BeaconFetchException([super.message]);
}

final class BeaconUpdateException extends BeaconException {
  const BeaconUpdateException([super.message]);
}

final class BeaconDeleteException extends BeaconException {
  const BeaconDeleteException([super.message]);
}
