/// Hint-only denial reason for hierarchy capability queries.
enum BeaconHierarchyDenialCode {
  notAdmitted,
  parentNotCoordinatable,
  parentTerminal,
  parentDeleted,
  parentDraft,
  blocked,
  childCreateForbidden,
}
