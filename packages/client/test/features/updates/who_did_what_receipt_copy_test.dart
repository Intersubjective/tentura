import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

/// #516 / #486 — the author's update says who did what, why, and (for a
/// helper who left) whether the next step still names them.
void main() {
  final en = L10nEn();
  final ru = L10nRu();

  String withdrawn({
    bool left = true,
    bool flagged = false,
    String excerpt = '',
    String reasonKey = 'timing',
  }) => jsonEncode({
    'eventType': 'helpWithdrawn',
    'beaconId': 'B1',
    'actorUserId': 'U1',
    'withdrawReason': reasonKey,
    'leftDiscussion': left,
    'nextStepMentionsActor': flagged,
    'excerpt': excerpt,
  });

  test('a helper who left: name, reason, note and the next-step flag', () {
    final copy = whoDidWhatReceiptDisplayCopy(
      title: 'Omar Dinner',
      presentationKey: 'help_withdrawn',
      presentationPayloadJson: withdrawn(
        flagged: true,
        excerpt: 'Saturday fell through',
      ),
      l10n: en,
    )!;
    expect(copy.headline, startsWith('Omar Dinner left the request ('));
    expect(copy.headline, contains(en.withdrawTimingChanged));
    expect(copy.body, contains('Saturday fell through'));
    expect(copy.body, contains(en.attentionEventNextStepNamesLeaver));
  });

  test('a pending offer withdrawn reads as an offer, not a leave', () {
    final copy = whoDidWhatReceiptDisplayCopy(
      title: 'Priya',
      presentationKey: 'help_withdrawn',
      presentationPayloadJson: withdrawn(left: false, reasonKey: 'wrong_fit'),
      l10n: ru,
      actorName: 'Прия',
    )!;
    expect(copy.headline, startsWith('Прия отозвал(а) предложение помощи'));
    expect(copy.headline, contains(ru.withdrawWrongFit));
    expect(copy.body, isEmpty);
  });

  test("Can't help: the recipient's name and their note", () {
    final payload = jsonEncode({
      'eventType': 'forwardDeclined',
      'beaconId': 'B1',
      'excerpt': 'Away that weekend',
    });
    final copy = whoDidWhatReceiptDisplayCopy(
      title: 'Nina Mover',
      presentationKey: 'forward_declined',
      presentationPayloadJson: payload,
      l10n: en,
    )!;
    expect(copy.headline, "Nina Mover can't help");
    expect(copy.body, 'Away that weekend');

    final scoped = requestScopedEventCopy(
      title: 'Nina Mover',
      body: "Nina Mover can't help: Away that weekend",
      presentationKey: 'forward_declined',
      presentationPayloadJson: payload,
      l10n: ru,
      requestTitle: 'Moving day',
    );
    expect(scoped.event, 'Nina Mover не может помочь');
    expect(scoped.excerpt, 'Away that weekend');
  });

  test('no name falls back to a localized label; other receipts pass', () {
    final copy = whoDidWhatReceiptDisplayCopy(
      title: '',
      presentationKey: 'forward_declined',
      presentationPayloadJson: '{}',
      l10n: en,
    )!;
    expect(copy.headline, en.updatesFallbackTitleForwardDeclined);
    expect(
      whoDidWhatReceiptDisplayCopy(
        title: 'X',
        presentationKey: 'offer_declined',
        presentationPayloadJson: '{"eventType":"offerDeclined"}',
        l10n: en,
      ),
      isNull,
    );
  });
}
