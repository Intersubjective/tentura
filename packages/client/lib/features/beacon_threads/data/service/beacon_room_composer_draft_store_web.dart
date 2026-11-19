import 'package:web/web.dart' as web;

// Tab-scoped sessionStorage: survives a full page reload of the same tab and
// stays per beacon id; closing the tab drops it. Sign-out clears every draft
// (clearAllBeaconRoomComposerDrafts) so the next account in the tab never sees
// the previous account's text. Storage can be blocked or full: every access is
// guarded and falls back to "no draft".
const _prefix = 'tentura.beaconRoomComposerDraft.';

String? readBeaconRoomComposerDraft(String beaconId) {
  try {
    return web.window.sessionStorage.getItem('$_prefix$beaconId');
  } catch (_) {
    return null;
  }
}

void writeBeaconRoomComposerDraft({
  required String beaconId,
  required String body,
}) {
  if (body.trim().isEmpty) {
    clearBeaconRoomComposerDraft(beaconId);
    return;
  }
  try {
    web.window.sessionStorage.setItem('$_prefix$beaconId', body);
  } catch (_) {}
}

void clearBeaconRoomComposerDraft(String beaconId) {
  try {
    web.window.sessionStorage.removeItem('$_prefix$beaconId');
  } catch (_) {}
}

void clearAllBeaconRoomComposerDrafts() {
  try {
    final storage = web.window.sessionStorage;
    for (var i = storage.length - 1; i >= 0; i--) {
      final key = storage.key(i);
      if (key != null && key.startsWith(_prefix)) storage.removeItem(key);
    }
  } catch (_) {}
}

void resetBeaconRoomComposerDraftStoreForTest() =>
    clearAllBeaconRoomComposerDrafts();
