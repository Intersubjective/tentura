import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

// #700 follow-up: when the actor's profile is not loaded, the Updates row
// learned who acted only by parsing the stored English title. The server now
// writes the actor's display name into the receipt payload (`actorName`);
// the row prefers the live profile, then that name, then the title.

const _request = 'QA700 trail';

String _payload(String eventType, {String? actorName}) => jsonEncode({
  'eventType': eventType,
  'personal': true,
  'actorUserId': 'u-actor',
  'beaconId': 'B1',
  'targetEntityId': 'u-target',
  'beaconTitle': _request,
  'excerpt': '',
  'actorName': ?actorName,
});

UpdatesFeedRowCopy _row(
  L10n l10n, {
  required String eventType,
  required String presentationKey,
  String title = '',
  String? payloadName,
  String? liveName,
}) => resolveUpdatesFeedRowCopy(
  title: title,
  body: '',
  presentationKey: presentationKey,
  presentationPayloadJson: _payload(eventType, actorName: payloadName),
  l10n: l10n,
  actorName: liveName,
);

void main() {
  final en = L10nEn();
  final ru = L10nRu();

  group('offer accepted row names the actor from the payload (#700)', () {
    test('RU: payload name with an unparseable title', () {
      final copy = _row(
        ru,
        eventType: 'offerAccepted',
        presentationKey: 'offer_accepted',
        title: 'Offer accepted',
        payloadName: 'Алиса',
      );
      expect(copy.headline, 'Алиса принял(а) ваше предложение');
      expect(copy.body, _request);
    });

    test('the payload name wins over the parsed title', () {
      final copy = _row(
        en,
        eventType: 'offerAccepted',
        presentationKey: 'offer_accepted',
        title: 'Title Name accepted your offer',
        payloadName: 'Payload Name',
      );
      expect(copy.headline, 'Payload Name accepted your offer');
    });

    test('the live profile wins over the payload name', () {
      final copy = _row(
        en,
        eventType: 'offerAccepted',
        presentationKey: 'offer_accepted',
        title: 'Title Name accepted your offer',
        payloadName: 'Payload Name',
        liveName: 'Live Name',
      );
      expect(copy.headline, 'Live Name accepted your offer');
    });

    test('a row written before the field still parses the title', () {
      final copy = _row(
        ru,
        eventType: 'offerAccepted',
        presentationKey: 'offer_accepted',
        title: 'Alice GQ2 accepted your offer',
      );
      expect(copy.headline, 'Alice GQ2 принял(а) ваше предложение');
    });

    test('a blank payload name falls back to the title', () {
      final copy = _row(
        en,
        eventType: 'offerAccepted',
        presentationKey: 'offer_accepted',
        title: 'Alice GQ2 accepted your offer',
        payloadName: '   ',
      );
      expect(copy.headline, 'Alice GQ2 accepted your offer');
    });
  });

  test('a help offer row names the helper from the payload (#700)', () {
    final copy = _row(
      ru,
      eventType: 'helpOfferSubmitted',
      presentationKey: 'help_offer_submitted',
      payloadName: 'Ева',
    );
    expect(copy.headline, 'Ева предложил(а) помощь');
  });

  test('an invite answer row names the invitee from the payload (#700)', () {
    final declined = _row(
      ru,
      eventType: 'authorInviteDeclined',
      presentationKey: 'author_invite_declined',
      payloadName: 'Борис',
    );
    expect(declined.headline, 'Борис не сможет');
    final accepted = _row(
      en,
      eventType: 'authorInviteAccepted',
      presentationKey: 'author_invite_accepted',
      title: 'Invitation accepted',
      payloadName: 'Bob',
    );
    expect(accepted.headline, 'Bob accepted your invite');
  });

  test('actorNameFromPresentationPayload reads a non-blank name only', () {
    expect(
      actorNameFromPresentationPayload(
        _payload('offerAccepted', actorName: ' Alice '),
      ),
      'Alice',
    );
    expect(
      actorNameFromPresentationPayload(
        _payload('offerAccepted', actorName: ''),
      ),
      isNull,
    );
    expect(actorNameFromPresentationPayload(_payload('offerAccepted')), isNull);
    expect(actorNameFromPresentationPayload(''), isNull);
  });
}
