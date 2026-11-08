/// In-memory Post/Request room reply draft, keyed by beacon id (same session).
final _draftByBeaconId = <String, String>{};

String? readBeaconRoomComposerDraft(String beaconId) =>
    _draftByBeaconId[beaconId];

void writeBeaconRoomComposerDraft({
  required String beaconId,
  required String body,
}) {
  if (body.trim().isEmpty) {
    clearBeaconRoomComposerDraft(beaconId);
    return;
  }
  _draftByBeaconId[beaconId] = body;
}

void clearBeaconRoomComposerDraft(String beaconId) {
  _draftByBeaconId.remove(beaconId);
}

void resetBeaconRoomComposerDraftStoreForTest() {
  _draftByBeaconId.clear();
}
