import 'package:web/web.dart' as web;

// Tab-scoped sessionStorage: survives a full page reload of the same tab and
// stays per beacon id; closing the tab drops it.
const _prefix = 'tentura.beaconRoomComposerDraft.';

String? readBeaconRoomComposerDraft(String beaconId) =>
    web.window.sessionStorage.getItem('$_prefix$beaconId');

void writeBeaconRoomComposerDraft({
  required String beaconId,
  required String body,
}) {
  if (body.trim().isEmpty) {
    clearBeaconRoomComposerDraft(beaconId);
    return;
  }
  web.window.sessionStorage.setItem('$_prefix$beaconId', body);
}

void clearBeaconRoomComposerDraft(String beaconId) {
  web.window.sessionStorage.removeItem('$_prefix$beaconId');
}

void resetBeaconRoomComposerDraftStoreForTest() {
  final storage = web.window.sessionStorage;
  for (var i = storage.length - 1; i >= 0; i--) {
    final key = storage.key(i);
    if (key != null && key.startsWith(_prefix)) storage.removeItem(key);
  }
}
