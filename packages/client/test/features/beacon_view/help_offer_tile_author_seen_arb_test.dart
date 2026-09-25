// tentura-id8.18: en/ru ARB entries for the offerer's author-seen row.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  test('en ARB values for the new keys', () {
    final en = lookupL10n(const Locale('en'));
    expect(en.helpOfferAuthorNotSeenYet, 'Sent · not seen by the author yet');
    expect(en.helpOfferAuthorSeen, 'Seen by the author · awaiting decision');
    expect(en.helpOfferAuthorSeenAtTooltip('T'), 'Seen T');
  });

  test('ru ARB values for the new keys', () {
    final ru = lookupL10n(const Locale('ru'));
    expect(ru.helpOfferAuthorNotSeenYet, 'Отправлено · автор пока не видел');
    expect(ru.helpOfferAuthorSeen, 'Автор видел · ждём решения');
    expect(ru.helpOfferAuthorSeenAtTooltip('T'), 'Просмотрено T');
  });
}
