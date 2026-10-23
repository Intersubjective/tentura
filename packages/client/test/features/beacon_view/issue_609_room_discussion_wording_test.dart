// Issue #609 (#481 follow-up): the room button in the request app bar
// (beacon_view_app_bar_overflow.dart) is labelled «Discussion», not
// «General»; the inbox card's room lines and the updates fallback body use
// the same word.
//
// Needs l10n regen after the ARB change (the generated getters carry the
// strings).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _author = Profile(id: 'Uauthor', displayName: 'Author');

BeaconViewState _authorState() => BeaconViewState(
  beacon: Beacon(
    id: 'B609',
    title: 'Room beacon',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    author: _author,
  ),
  myProfile: _author,
);

void main() {
  final en = lookupL10n(const Locale('en'));
  final ru = lookupL10n(const Locale('ru'));

  test('guard: the author can open the room from the app bar', () {
    expect(_authorState().canNavigateBeaconRoom, isTrue);
  });

  test('app-bar room button says Discussion (en)', () {
    expect(beaconViewRoomAppBarTooltip(_authorState(), en), 'Discussion');
  });

  test('app-bar room button says Обсуждение (ru)', () {
    expect(beaconViewRoomAppBarTooltip(_authorState(), ru), 'Обсуждение');
  });

  test('inbox card room lines name the discussion', () {
    expect(en.inboxCardRoomUnread(0), 'Discussion up to date');
    expect(en.inboxCardRoomUnread(3), '3 unread in the discussion');
    expect(en.inboxCardRoomCurrentLine('Bring chairs'), contains('discussion'));
    expect(en.inboxCardRoomLastChange('Bring chairs'), contains('discussion'));
    expect(ru.inboxCardRoomUnread(5), '5 непрочитанных в обсуждении');
    expect(ru.inboxCardRoomCurrentLine('Стулья'), contains('обсуждении'));
    for (final l10n in [en, ru]) {
      expect(l10n.inboxCardRoomUnread(1), isNot(contains('General')));
      expect(l10n.inboxCardRoomUnread(1), isNot(contains('Общ')));
    }
  });

  test('updates fallback for a redirected commitment opens the discussion', () {
    expect(
      en.updatesFallbackBodyCommitmentRedirected,
      'Open the discussion to see your assignment.',
    );
    expect(
      ru.updatesFallbackBodyCommitmentRedirected,
      'Откройте обсуждение, чтобы увидеть назначение.',
    );
  });
}
