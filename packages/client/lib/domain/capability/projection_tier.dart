/// Server [ProjectionTier] wire values (camelCase enum names).
enum ProjectionTier {
  ownOutcome,
  networkOutcome,
  ownRouting,
  networkSeed;

  static ProjectionTier fromWire(String raw) => ProjectionTier.values.firstWhere(
    (tier) => tier.name == raw,
    orElse: () => throw ArgumentError.value(raw, 'raw', 'unknown projection tier'),
  );
}
