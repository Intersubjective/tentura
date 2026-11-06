/// Recipient state marker on a person node in forward-tree Field mode (#774).
enum ConstellationForwardTreeRecipientMarker {
  /// Helped (accepted offer path).
  helped,

  /// Active offer, not yet accepted on this edge context.
  offered,

  /// Cannot help (declined, etc.).
  cantHelp,

  /// Forward opened/read (middle dot).
  opened,

  /// Forward not opened (hollow).
  notOpened,
}
