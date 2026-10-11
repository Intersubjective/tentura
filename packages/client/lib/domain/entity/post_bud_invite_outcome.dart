/// Per-invitee outcome of a Post bud or a later author invite (plan §0).
///
/// One enum shared with the server; the wire value is [name]. In the invite
/// candidate list, [invited] means «can be invited now».
enum PostBudInviteOutcome {
  invited,
  notEligible,
  alreadyInvited,
  recipientPaused,
  blocked;

  /// Unknown wire values read as [notEligible]: never offer an invite the
  /// client cannot classify.
  static PostBudInviteOutcome fromWire(String raw) =>
      values.firstWhere((o) => o.name == raw, orElse: () => notEligible);
}
