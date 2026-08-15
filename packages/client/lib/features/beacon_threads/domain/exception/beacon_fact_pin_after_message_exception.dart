/// Message was posted, but pinning the fact card failed.
final class BeaconFactPinAfterMessageException implements Exception {
  const BeaconFactPinAfterMessageException({
    required this.messageId,
    required this.cause,
  });

  final String messageId;
  final Object cause;

  @override
  String toString() =>
      'BeaconFactPinAfterMessageException($messageId, $cause)';
}
