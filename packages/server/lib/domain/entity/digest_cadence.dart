/// How often a user receives the batched "what's waiting / what moved" email.
enum DigestCadence {
  off,
  daily,
  weekly,
}

/// Parse a cadence from its persisted name, falling back to [DigestCadence.off].
DigestCadence digestCadenceFromName(String? name) {
  for (final c in DigestCadence.values) {
    if (c.name == name) {
      return c;
    }
  }
  return DigestCadence.off;
}
