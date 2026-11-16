import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

// Updates rows name the person and show the facts the event carries
// (names, message text, Post identity, linked Request, closure, stale, trust)
// instead of a nameless headline or raw enum/ISO values.

UpdatesFeedRowCopy _row(
  L10n l10n,
  String key, {
  Map<String, Object?> payload = const {},
  String? actor = 'Anna',
  String title = '',
  String body = '',
  String? relatedBeaconTitle,
}) => resolveUpdatesFeedRowCopy(
  title: title,
  body: body,
  presentationKey: key,
  presentationPayloadJson: jsonEncode({
    'personal': true,
    'beaconId': 'B1',
    'beaconTitle': 'Fix the roof',
    ...payload,
  }),
  l10n: l10n,
  actorName: actor,
  relatedBeaconTitle: relatedBeaconTitle,
);

void main() {
  final en = L10nEn();
  final ru = L10nRu();

  group('linked Request status', () {
    const statuses = {
      'closed': ('was closed', 'закрыт'),
      'cancelled': ('was cancelled', 'отменён'),
      // `reviewOpen` is the BeaconStatus wire name the server writes into the
      // payload's toStatus for «Final check» (spec §5.2: «entered Final check»).
      'reviewOpen': ('entered Final check', 'на подведении итогов'),
      'deleted': ('was deleted', 'удалён'),
    };
    statuses.forEach((to, words) {
      test('toStatus $to with title', () {
        expect(
          _row(
            en,
            'beacon_hierarchy_status_changed',
            payload: {'toStatus': to},
            relatedBeaconTitle: 'Buy paint',
          ).headline,
          'Linked request «Buy paint» ${words.$1}',
        );
        expect(
          _row(
            ru,
            'beacon_hierarchy_status_changed',
            payload: {'toStatus': to},
            relatedBeaconTitle: 'Buy paint',
          ).headline,
          'Связанный запрос «Buy paint» ${words.$2}',
        );
        for (final l in [en, ru]) {
          final c = _row(
            l,
            'beacon_hierarchy_status_changed',
            payload: {'toStatus': to},
            relatedBeaconTitle: 'Buy paint',
          );
          expect(c.body, isNot(contains(to)));
          expect(c.body, isNot(contains('Buy paint')));
        }
      });
    });
    test('unreadable linked Request drops the title and quotes', () {
      final p = {'toStatus': 'closed'};
      expect(
        _row(en, 'beacon_hierarchy_status_changed', payload: p).headline,
        'A linked request was closed',
      );
      expect(
        _row(ru, 'beacon_hierarchy_status_changed', payload: p).headline,
        'Связанный запрос закрыт',
      );
    });
  });
}
