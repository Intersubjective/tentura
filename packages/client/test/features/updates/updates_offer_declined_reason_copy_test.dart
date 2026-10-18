import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

// #381 — the Updates row for a declined offer (also the Timeline sheet row:
// both use `resolveUpdatesFeedRowCopy`) carries the author's reason. Today
// `line2` prefers `beaconTitle` over the excerpt, so the reason is dropped.

const _reason = 'Thanks, but we already found a van';
const _requestTitle = 'Child: borrow moving straps';

String _payload({String? excerpt = _reason}) => jsonEncode({
  'eventType': 'offerDeclined',
  'actorUserId': 'a1',
  'beaconId': 'b1',
  'targetEntityId': 'helper',
  'beaconTitle': _requestTitle,
  'excerpt': ?excerpt,
});

UpdatesFeedRowCopy _row(
  L10n l10n, {
  String? excerpt = _reason,
  String body = '$_requestTitle — $_reason',
}) => resolveUpdatesFeedRowCopy(
  title: 'Offer declined',
  body: body,
  presentationKey: 'offer_declined',
  presentationPayloadJson: _payload(excerpt: excerpt),
  l10n: l10n,
  actorName: 'Tab QA',
);

String _whole(UpdatesFeedRowCopy copy) => '${copy.headline}\n${copy.body}';

void main() {
  final en = L10nEn();
  final ru = L10nRu();

  test('en: the row names the decline, the request and the reason', () {
    final whole = _whole(_row(en));
    expect(whole, contains(_reason));
    expect(whole, contains(_requestTitle));
    expect(whole.toLowerCase(), contains('declined'));
    // Once, not twice.
    expect(_reason.allMatches(whole), hasLength(1));
  });

  test('ru: the row names the decline in Russian, the request and the '
      'reason', () {
    final whole = _whole(_row(ru));
    expect(whole, contains(_reason));
    expect(whole, contains(_requestTitle));
    expect(whole.toLowerCase(), contains('отклон'));
    expect(whole, isNot(contains('declined')));
  });

  test('guard: a decline without words keeps today’s row', () {
    for (final (l10n, headline) in [
      (en, 'Offer declined'),
      (ru, 'Предложение отклонено'),
    ]) {
      final copy = _row(l10n, excerpt: '', body: _requestTitle);
      expect(copy.headline, headline);
      expect(copy.body, _requestTitle);
      expect(_whole(copy), isNot(matches(RegExp(r':\s*$', multiLine: true))));
    }
  });

  test('guard: no structured excerpt means no words, even when the push '
      'body carries them', () {
    for (final l10n in [en, ru]) {
      final whole = _whole(_row(l10n, excerpt: ''));
      expect(whole, isNot(contains(_reason)));
      expect(whole, contains(_requestTitle));
    }
  });
}
