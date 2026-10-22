import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

// #516 residual (option A, Vadim 2026-10-22): a helper withdrawal reaches the
// author as a `promiseWithdrawn` receipt whose payload carries the reason key
// (`withdrawReason`) and the helper's note (`excerpt`). Under a Request header
// (Timeline, mini-cards) it reads today as «Promise withdrawn» /
// «Обещание отозвано»: neither who left nor why. Pinned: the room line's own
// copy, `beaconRoomParticipantLeft(name, withdrawReasonLabel(key))`, with the
// note as the excerpt.

const _note = 'Sorry, Saturday morning fell through';
const _requestTitle = 'Move a sofa';

RequestScopedEventCopy _copy(
  L10n l10n, {
  String? withdrawReason = 'timing',
  String excerpt = _note,
  String? coordinationItemId,
}) => requestScopedEventCopy(
  title: 'Nina Mover',
  body: excerpt.isEmpty ? 'Nina Mover withdrew their help' : excerpt,
  presentationKey: 'promise_withdrawn',
  presentationPayloadJson: jsonEncode({
    'eventType': 'promiseWithdrawn',
    'personal': false,
    'actorUserId': 'h1',
    'beaconId': 'b1',
    'targetEntityId': 'h1',
    'coordinationItemId': ?coordinationItemId,
    'beaconTitle': _requestTitle,
    'withdrawReason': ?withdrawReason,
    'excerpt': excerpt,
  }),
  requestTitle: _requestTitle,
  actorName: 'Nina Mover',
  l10n: l10n,
);

void main() {
  final en = L10nEn();
  final ru = L10nRu();

  group('#516 helper withdrawal reads as who left and why', () {
    test('en: the event names the helper and the reason, the note is the '
        'excerpt', () {
      final copy = _copy(en);
      expect(copy.event, 'Nina Mover left the request (Timing no longer works)');
      expect(copy.excerpt, _note);
    });

    test('ru: the same in Russian', () {
      final copy = _copy(ru);
      expect(
        copy.event,
        'Nina Mover покинул(а) запрос (Не сходится по времени)',
      );
      expect(copy.excerpt, _note);
    });

    test('no note: the event alone, no excerpt', () {
      final copy = _copy(en, withdrawReason: 'cannot_do_it', excerpt: '');
      expect(copy.event, 'Nina Mover left the request (Cannot do it anymore)');
      expect(copy.excerpt, isEmpty);
    });

    test('guard: a withdrawn promise keeps its own copy', () {
      for (final l10n in [en, ru]) {
        final copy = _copy(
          l10n,
          withdrawReason: null,
          excerpt: 'Cannot bring the van',
          coordinationItemId: 'item1',
        );
        expect(copy.event, l10n.updatesFallbackTitlePromiseWithdrawn);
        expect(copy.excerpt, 'Cannot bring the van');
      }
    });
  });
}
