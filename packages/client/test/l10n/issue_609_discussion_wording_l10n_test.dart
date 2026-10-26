import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Issue #609 (#481 follow-up): the request room's one thread is called
// «Discussion» / «Обсуждение» everywhere the user sees it, not «General» /
// «Общее». The inbox category «General» is a different thing and stays.
//
// Run from packages/client: the ARB files are read by relative path.
Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

const _roomKeys = [
  'threadGeneralTitle',
  'beaconRoomTitle',
  'beaconRoomOpen',
  'beaconSituationOpenRoom',
  'beaconCloseSheetActionResolveRoom',
  'beaconBlockersPanelAskInRoom',
  'beaconDefinitionLastRoomChangeLabel',
  'beaconRoomStripOpenBlockerHint',
  'inboxCardRoomUnread',
  'inboxCardRoomCurrentLine',
  'inboxCardRoomLastChange',
  'updatesFallbackBodyCommitmentRedirected',
];

void main() {
  final en = _arb('l10n/app_en.arb');
  final ru = _arb('l10n/app_ru.arb');

  test('en: room strings say discussion, never General', () {
    for (final key in _roomKeys) {
      final value = en[key] as String;
      expect(value, isNot(contains('General')), reason: key);
      expect(value.toLowerCase(), contains('discussion'), reason: key);
    }
  });

  test('ru: room strings say обсуждение, never Общее', () {
    for (final key in _roomKeys) {
      final value = ru[key] as String;
      expect(value, isNot(contains('Общ')), reason: key);
      expect(value.toLowerCase(), contains('обсужд'), reason: key);
    }
  });

  test('the room title and its open labels read as decided', () {
    for (final key in [
      'threadGeneralTitle',
      'beaconRoomTitle',
      'beaconRoomOpen',
    ]) {
      expect(en[key], 'Discussion', reason: key);
      expect(ru[key], 'Обсуждение', reason: key);
    }
    for (final key in [
      'beaconSituationOpenRoom',
      'beaconCloseSheetActionResolveRoom',
    ]) {
      expect(en[key], 'Open discussion', reason: key);
      expect(ru[key], 'Открыть обсуждение', reason: key);
    }
    expect(en['beaconBlockersPanelAskInRoom'], 'Ask in discussion');
    expect(ru['beaconBlockersPanelAskInRoom'], 'Спросить в обсуждении');
    expect(en['beaconDefinitionLastRoomChangeLabel'], 'Last in discussion');
    expect(
      ru['beaconDefinitionLastRoomChangeLabel'],
      'Последнее в обсуждении',
    );
  });

  test('placeholders survive the rename', () {
    for (final arb in [en, ru]) {
      expect(arb['inboxCardRoomUnread'], contains('{count}'));
      expect(arb['inboxCardRoomCurrentLine'], contains('{text}'));
      expect(arb['inboxCardRoomLastChange'], contains('{text}'));
    }
    expect(ru['inboxCardRoomUnread'], contains('few{'));
    expect(ru['inboxCardRoomUnread'], contains('many{'));
  });

  test('guard: the inbox category General keeps its own wording', () {
    expect(en['inboxCategoryGeneral'], 'General');
    expect(ru['inboxCategoryGeneral'], 'Общее');
  });

  // QA 7.50.3 follow-up: the request room's tab and the labels that lead
  // back into it said «Chat» / «Чат». A Post's own chat is a different thing
  // and keeps its wording (guard below).
  test('room tab and its chat labels say discussion, en and ru', () {
    expect(en['labelBeaconTabChat'], 'Discussion');
    expect(ru['labelBeaconTabChat'], 'Обсуждение');
    expect(en['beaconRoomBackToChat'], 'Back to Discussion');
    expect(ru['beaconRoomBackToChat'], 'К обсуждению');
    expect(en['beaconRoomFactCardActionQuoteInChat'], 'Quote in discussion');
    expect(
      ru['beaconRoomFactCardActionQuoteInChat'],
      'Цитировать в обсуждении',
    );
    expect(
      en['beaconOutcomeReadOnlyNote'],
      'No new offers or messages. The discussion stays readable.',
    );
    expect(ru['beaconOutcomeReadOnlyNote'], contains('обсуждение'));
    for (final key in [
      'labelBeaconTabChat',
      'beaconRoomBackToChat',
      'beaconRoomFactCardActionQuoteInChat',
      'beaconOutcomeReadOnlyNote',
    ]) {
      expect(
        (en[key] as String).toLowerCase(),
        isNot(contains('chat')),
        reason: key,
      );
      expect(
        (ru[key] as String).toLowerCase(),
        isNot(contains('чат')),
        reason: key,
      );
    }
  });

  // #720 (option A): Post strings say «post», not «chat» or «discussion».
  test('guard: Post strings keep their post wording', () {
    expect(en['postMenuLeave'], 'Leave post');
    expect(ru['postMenuLeave'], 'Выйти из поста');
    expect(en['postsTabNewPost'], 'New post');
    expect(ru['postsTabNewPost'], 'Новый пост');
  });
}
