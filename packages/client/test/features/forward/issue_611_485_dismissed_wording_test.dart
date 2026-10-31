import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

/// #611 › #485: a request someone set aside reads "dismissed" everywhere on
/// the request side, including the Forward-to-person row's disabled reason
/// (it said "Declined", the word kept for help offers).
void main() {
  test('Forward to person: a dismissed request reads «Dismissed»', () {
    expect(L10nEn().beaconForwardPersonReasonDeclined, 'Dismissed');
    expect(L10nRu().beaconForwardPersonReasonDeclined, 'Убрано');
  });

  test('the other request-side lines already say dismissed', () {
    final en = L10nEn();
    expect(en.forwardDeclined, 'Dismissed this request');
    expect(en.myForwardDeclined, 'Dismissed');
    expect(en.activityForwardOutcomeNotInterested, 'You dismissed it');
  });
}
