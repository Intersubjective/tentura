import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/l10n/l10n.dart';

// Review of #707: the ru plural had `=1{…}` and no `one{}`, so 21 fell
// through to «голосов». Run after l10n regen.
void main() {
  final ru = lookupL10n(const Locale('ru'));
  final en = lookupL10n(const Locale('en'));

  test('ru closed-poll vote count agrees with the number', () {
    expect(ru.beaconRoomPollClosedVotesCount(0), 'Опрос закрыт · Нет голосов');
    expect(ru.beaconRoomPollClosedVotesCount(1), 'Опрос закрыт · 1 голос');
    expect(ru.beaconRoomPollClosedVotesCount(2), 'Опрос закрыт · 2 голоса');
    expect(ru.beaconRoomPollClosedVotesCount(5), 'Опрос закрыт · 5 голосов');
    expect(ru.beaconRoomPollClosedVotesCount(21), 'Опрос закрыт · 21 голос');
    expect(ru.beaconRoomPollClosedVotesCount(22), 'Опрос закрыт · 22 голоса');
    expect(ru.beaconRoomPollClosedVotesCount(11), 'Опрос закрыт · 11 голосов');
  });

  test('guard: en closed-poll vote count', () {
    expect(en.beaconRoomPollClosedVotesCount(1), 'Poll closed · 1 vote');
    expect(en.beaconRoomPollClosedVotesCount(21), 'Poll closed · 21 votes');
  });
}
