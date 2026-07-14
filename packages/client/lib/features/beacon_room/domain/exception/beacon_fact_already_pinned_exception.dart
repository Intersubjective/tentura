/// The requested room message already has a pinned fact card.
final class BeaconFactAlreadyPinnedException implements Exception {
  const BeaconFactAlreadyPinnedException({required this.factCardId});

  final String factCardId;

  /// Tentura V2 GraphQL code: 1300 + enum index 3.
  static const codeNumber = 1303;

  @override
  String toString() => 'BeaconFactAlreadyPinnedException($factCardId)';
}
