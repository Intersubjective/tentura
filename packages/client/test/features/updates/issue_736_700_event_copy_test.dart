import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

// #736a: the author's Updates rows for an invitee's answer
// (`authorInviteAccepted` / `authorInviteDeclined`) said only the person's
// name — the server titles them with the name and the event lived nowhere.
// #700: closure notices («Time to sum up», «Request closed», «The results
// are in.») stayed English in the Russian UI — the server writes fixed
// English copy on those rows. Both now come from the locale by event.

const _request = 'Garden cleanup Saturday';

String _invitePayload(String eventType, {bool withTitle = true}) => jsonEncode({
  'eventType': eventType,
  'personal': true,
  'actorUserId': 'u-bob',
  'beaconId': 'B1',
  'targetEntityId': 'u-bob',
  'beaconTitle': ?(withTitle ? _request : null),
  'excerpt': '',
});

UpdatesFeedRowCopy _inviteRow(
  L10n l10n,
  String eventType, {
  required String body,
  bool withTitle = true,
  String? actorName,
}) => resolveUpdatesFeedRowCopy(
  title: 'Bob GQ',
  body: body,
  presentationKey: eventType == 'authorInviteAccepted'
      ? 'author_invite_accepted'
      : 'author_invite_declined',
  presentationPayloadJson: _invitePayload(eventType, withTitle: withTitle),
  l10n: l10n,
  actorName: actorName,
);

String _closurePayload(String eventType) => jsonEncode({
  'eventType': eventType,
  'beaconId': 'B1',
  'epoch': 1,
});

UpdatesFeedRowCopy _closureRow(
  L10n l10n, {
  required String eventType,
  required String presentationKey,
  required String title,
  required String body,
}) => resolveUpdatesFeedRowCopy(
  title: title,
  body: body,
  presentationKey: presentationKey,
  presentationPayloadJson: _closurePayload(eventType),
  l10n: l10n,
);

void main() {
  final en = L10nEn();
  final ru = L10nRu();

  group('author-invite answers say what happened (#736a)', () {
    test('accepted: the row says the person accepted, in each locale', () {
      for (final (l10n, line) in <(L10n, String)>[
        (en, 'Bob GQ accepted your invite'),
        (ru, 'Bob GQ принял(а) приглашение'),
      ]) {
        final copy = _inviteRow(
          l10n,
          'authorInviteAccepted',
          body: 'Bob GQ accepted your invitation',
        );
        expect(copy.headline, line, reason: l10n.localeName);
        expect(copy.body, _request, reason: l10n.localeName);
      }
    });

    test('declined: the row says the person cannot make it', () {
      for (final (l10n, line) in <(L10n, String)>[
        (en, "Bob GQ can't make it"),
        (ru, 'Bob GQ не сможет'),
      ]) {
        final copy = _inviteRow(
          l10n,
          'authorInviteDeclined',
          body: "Bob GQ can't help",
          withTitle: false,
        );
        expect(copy.headline, line, reason: l10n.localeName);
        expect(copy.body, isEmpty, reason: l10n.localeName);
      }
    });

    test('the known contact name wins over the server title', () {
      final copy = _inviteRow(
        en,
        'authorInviteAccepted',
        body: 'Bob GQ accepted your invitation',
        actorName: 'Bobby',
      );
      expect(copy.headline, 'Bobby accepted your invite');
    });

    test('inside a Request card the event is named too', () {
      final copy = requestScopedEventCopy(
        title: 'Bob GQ',
        body: 'Bob GQ accepted your invitation',
        presentationKey: 'author_invite_accepted',
        presentationPayloadJson: _invitePayload('authorInviteAccepted'),
        l10n: ru,
        requestTitle: _request,
      );
      expect(copy.event, 'Bob GQ принял(а) приглашение');
      expect(copy.excerpt, isEmpty);
    });
  });

  group('closure notices are localized (#700)', () {
    test('Russian: «Request closed — The results are in.»', () {
      final copy = _closureRow(
        ru,
        eventType: 'closureFinalized',
        presentationKey: 'closure_finalized',
        title: 'Request closed',
        body: 'The results are in.',
      );
      expect(copy.headline, 'Запрос закрыт');
      expect(copy.body, 'Итоги подведены.');
    });

    test('Russian: «Time to sum up», also on the bookmark-only row', () {
      for (final key in ['closure_opened', 'closure_opened_bookmark_only']) {
        final copy = _closureRow(
          ru,
          eventType: 'closureOpened',
          presentationKey: key,
          title: 'Time to sum up',
          body: 'The closing window is open.',
        );
        expect(copy.headline, 'Пора подвести итоги', reason: key);
        expect(copy.body, 'Подведение итогов началось.', reason: key);
      }
    });

    test('Russian: a cancelled final check', () {
      final copy = _closureRow(
        ru,
        eventType: 'closureCancelled',
        presentationKey: 'closure_cancelled',
        title: 'Evaluation cancelled',
        body: 'The closing was cancelled.',
      );
      expect(copy.headline, 'Оценка отменена');
      expect(copy.body, 'Подведение итогов отменено.');
    });

    test('guard: English keeps the same words', () {
      final finalized = _closureRow(
        en,
        eventType: 'closureFinalized',
        presentationKey: 'closure_finalized',
        title: 'Request closed',
        body: 'The results are in.',
      );
      expect(finalized.headline, 'Request closed');
      expect(finalized.body, 'The results are in.');
      final opened = _closureRow(
        en,
        eventType: 'closureOpened',
        presentationKey: 'closure_opened',
        title: 'Time to sum up',
        body: 'The closing window is open.',
      );
      expect(opened.headline, 'Time to sum up');
      expect(opened.body, 'The closing window is open.');
    });

    test('inside a Request card the closure event is Russian too', () {
      final copy = requestScopedEventCopy(
        title: 'Request closed',
        body: 'The results are in.',
        presentationKey: 'closure_finalized',
        presentationPayloadJson: _closurePayload('closureFinalized'),
        l10n: ru,
        requestTitle: _request,
      );
      expect(copy.event, 'Запрос закрыт');
      expect(copy.excerpt, isEmpty);
    });
  });
}
