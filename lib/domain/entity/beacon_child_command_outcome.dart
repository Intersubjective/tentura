/// Result discriminator for idempotent child create commands.
enum BeaconChildCommandOutcome {
  created,
  replayed,
  alreadyPromoted,
}
