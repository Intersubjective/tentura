/// How a new request is being created (standalone, nested child, or promotion).
sealed class BeaconCreationContext {
  const BeaconCreationContext();
}

/// Ordinary top-level request with no nesting parent.
final class BeaconCreationContextStandalone extends BeaconCreationContext {
  const BeaconCreationContextStandalone();
}

/// Child request nested under an existing published parent.
final class BeaconCreationContextChild extends BeaconCreationContext {
  const BeaconCreationContextChild({required this.parentBeaconId});

  final String parentBeaconId;
}

/// Child request seeded from a General message on the parent.
final class BeaconCreationContextPromotedChild extends BeaconCreationContext {
  const BeaconCreationContextPromotedChild({
    required this.parentBeaconId,
    required this.sourceMessageId,
  });

  final String parentBeaconId;
  final String sourceMessageId;
}
