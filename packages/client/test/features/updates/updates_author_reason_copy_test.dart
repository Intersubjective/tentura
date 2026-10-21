import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

// #601 (from #381) — the Updates row (also the Timeline sheet row) for a
// removal from the discussion or an ended participation carries the author's
// reason, the way #381 made the declined offer's row carry it. Today `line2`
// prefers `beaconTitle` and the reason is dropped.

const _reason = 'Sorry, we only need someone with a car for this one';
const _requestTitle = 'Child: borrow moving straps';

UpdatesFeedRowCopy _row(
  L10n l10n, {
  required String eventType,
  required String presentationKey,
  required String title,
  String? excerpt = _reason,
}) => resolveUpdatesFeedRowCopy(
  title: title,
  body: excerpt == null || excerpt.isEmpty
      ? _requestTitle
      : '$_requestTitle — $excerpt',
  presentationKey: presentationKey,
  presentationPayloadJson: jsonEncode({
    'eventType': eventType,
    'actorUserId': 'a1',
    'beaconId': 'b1',
    'targetEntityId': 'helper',
    'beaconTitle': _requestTitle,
    'excerpt': ?excerpt,
  }),
  l10n: l10n,
  actorName: 'Tab QA',
);

String _whole(UpdatesFeedRowCopy copy) => '${copy.headline}\n${copy.body}';

void main() {
  final en = L10nEn();
  final ru = L10nRu();

  for (final (eventType, presentationKey, title) in [
    ('offerRemoved', 'offer_removed', 'Removed from the discussion'),
    ('commitmentReleased', 'commitment_released', 'Participation ended'),
  ]) {
    group('#601 — $eventType', () {
      for (final l10n in [en, ru]) {
        test('${l10n.localeName}: the row names the request and the reason, '
            'once', () {
          final whole = _whole(
            _row(
              l10n,
              eventType: eventType,
              presentationKey: presentationKey,
              title: title,
            ),
          );
          expect(whole, contains(_reason));
          expect(whole, contains(_requestTitle));
          expect(_reason.allMatches(whole), hasLength(1));
        });

        test('${l10n.localeName} guard: without words the row keeps the '
            'request title and no dangling quote', () {
          final copy = _row(
            l10n,
            eventType: eventType,
            presentationKey: presentationKey,
            title: title,
            excerpt: '',
          );
          expect(copy.body, _requestTitle);
          expect(_whole(copy), isNot(contains(_reason)));
        });
      }
    });
  }
}
