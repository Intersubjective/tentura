sealed class InvitationException implements Exception {}

class InvitationDeleteException implements InvitationException {
  const InvitationDeleteException(this.id);

  final String id;
}

class InvitationAcceptException implements InvitationException {
  const InvitationAcceptException(this.id);

  final String id;
}

/// Invite row missing, consumed, or expired at accept time.
class InvitationNoLongerValid implements InvitationException {
  const InvitationNoLongerValid();
}

/// Self-invite or other bad request from accept-as-existing.
class InvitationSelfOrInvalid implements InvitationException {
  const InvitationSelfOrInvalid();
}

/// Bearer rejected while accepting (stale session).
class InvitationAuthLost implements InvitationException {
  const InvitationAuthLost();
}
