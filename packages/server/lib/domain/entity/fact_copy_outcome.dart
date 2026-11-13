/// What a single fact copy did in its destination (plan §5.4).
enum FactCopyOutcome {
  /// A new copy was inserted.
  created,

  /// The destination already holds a live copy of the source.
  alreadyThere,
}
