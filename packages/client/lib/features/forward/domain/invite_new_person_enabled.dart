/// Whether the Forward picker may mint a request-tied invite.
bool inviteNewPersonEnabled({
  required String beaconId,
  bool allowsForward = false,
  bool isLive = false,
}) => beaconId.isNotEmpty && (allowsForward || isLive);
