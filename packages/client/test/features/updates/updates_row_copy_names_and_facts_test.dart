import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/widgets.dart' show Characters;
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/features/beacon_view/domain/beacon_status_menu_presenter.dart';
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
  bool isPost = false,
  String? postRootExcerpt,
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
  isPost: isPost,
  postRootExcerpt: postRootExcerpt,
);

/// A row built without an actor name must not leak `null`, an empty name,
/// dangling punctuation or empty quotes.
void _expectNoNameArtifacts(UpdatesFeedRowCopy c) {
  final all = _all(c);
  expect(all, isNot(contains('null')));
  expect(all, isNot(contains('«»')));
  expect(all, isNot(contains('  ')));
  expect(c.headline, isNotEmpty);
  expect(c.headline, isNot(matches(RegExp(r'^[\s:,—-]'))));
  expect(c.headline, isNot(contains(' :')));
}

/// No raw ISO timestamp or date in a row.
void _expectNoRawIso(UpdatesFeedRowCopy c) {
  expect(_all(c), isNot(matches(RegExp(r'\d{4}-\d{2}-\d{2}'))));
  expect(_all(c), isNot(matches(RegExp(r'T\d{2}:\d{2}'))));
}

String _all(UpdatesFeedRowCopy c) => '${c.headline}\n${c.body}';

void main() {
  final en = L10nEn();
  final ru = L10nRu();
  const step = {'excerpt': 'Bring a ladder'};

  group('generic keys name the actor in the headline', () {
    final cases = <(String, Map<String, Object?>, String, String)>[
      (
        'offer_declined',
        {},
        'Anna declined your offer',
        'Anna отклонил(а) ваше предложение',
      ),
      (
        'offer_removed',
        {},
        'Anna removed you from the discussion',
        'Anna убрал(а) вас из обсуждения',
      ),
      (
        'commitment_released',
        {},
        'Anna ended your participation',
        'Anna завершил(а) ваше участие',
      ),
      (
        'coordination_changed',
        step,
        'Anna updated the coordination: Bring a ladder',
        'Anna: договорённости изменились — Bring a ladder',
      ),
      (
        'plan_change_pending',
        step,
        'Anna changed your step «Bring a ladder»',
        'Anna изменил(а) ваш шаг «Bring a ladder»',
      ),
      (
        'plan_cant_make',
        step,
        "Anna can't make «Bring a ladder»",
        'Anna не успевает к шагу «Bring a ladder»',
      ),
    ];
    final fallbackEn = {
      'offer_declined': en.updatesFallbackTitleOfferDeclined,
      'offer_removed': en.updatesFallbackTitleOfferRemoved,
      'commitment_released': en.updatesFallbackTitleCommitmentReleased,
      'coordination_changed': en.updatesFallbackTitleCoordinationChanged,
      'plan_change_pending': en.planReceiptChangePending,
      'plan_cant_make': en.planReceiptCantMake,
    };
    final fallbackRu = {
      'offer_declined': ru.updatesFallbackTitleOfferDeclined,
      'offer_removed': ru.updatesFallbackTitleOfferRemoved,
      'commitment_released': ru.updatesFallbackTitleCommitmentReleased,
      'coordination_changed': ru.updatesFallbackTitleCoordinationChanged,
      'plan_change_pending': ru.planReceiptChangePending,
      'plan_cant_make': ru.planReceiptCantMake,
    };
    for (final (key, payload, enText, ruText) in cases) {
      test('$key EN', () {
        expect(_row(en, key, payload: payload).headline, enText);
      });
      test('$key RU', () {
        expect(_row(ru, key, payload: payload).headline, ruText);
      });
      test('$key without an actor keeps its generic headline', () {
        final e = _row(en, key, payload: payload, actor: null);
        expect(e.headline, fallbackEn[key]);
        _expectNoNameArtifacts(e);
        final r = _row(ru, key, payload: payload, actor: null);
        expect(r.headline, fallbackRu[key]);
        _expectNoNameArtifacts(r);
      });
    }
  });

  group('status and deadline facts are formatted', () {
    test('status change names the existing localized status label', () {
      final p = {'toStatus': 'closed'};
      expect(
        _row(en, 'request_status_changed', payload: p).headline,
        'Anna changed the status to «${requestStatusActivityLabel(en, BeaconStatus.closed)}»',
      );
      expect(
        _row(ru, 'request_status_changed', payload: p).headline,
        'Anna: статус «Закрыт»',
      );
    });
    test('status change never shows the raw enum name', () {
      final p = {'toStatus': 'reviewOpen'};
      final e = _row(en, 'request_status_changed', payload: p);
      final label = requestStatusActivityLabel(en, BeaconStatus.reviewOpen);
      expect(e.headline, 'Anna changed the status to «$label»');
      expect(_all(e), isNot(contains('reviewOpen')));
    });

    final year = DateTime.now().year;
    final end = DateTime(year, 11, 21, 18).toIso8601String();
    test('deadline_changed with a date', () {
      expect(
        _row(en, 'deadline_changed', payload: {'newEndAt': end}).headline,
        'Anna moved the deadline to 21 Nov, 18:00',
      );
      expect(
        _row(ru, 'deadline_changed', payload: {'newEndAt': end}).headline,
        'Anna: новый срок — 21 ноября, 18:00',
      );
    });
    test('deadline_changed removed', () {
      expect(
        _row(en, 'deadline_changed', payload: {'newEndAt': null}).headline,
        'Anna removed the deadline',
      );
      expect(
        _row(ru, 'deadline_changed', payload: {'newEndAt': null}).headline,
        'Anna убрал(а) срок',
      );
    });
    test('deadline_reminder', () {
      expect(
        _row(en, 'deadline_reminder', payload: {'newEndAt': end}).headline,
        'Deadline: 21 Nov, 18:00',
      );
      expect(
        _row(ru, 'deadline_reminder', payload: {'newEndAt': end}).headline,
        'Срок: 21 ноября, 18:00',
      );
    });
    test('another year adds the year', () {
      final y = year + 5;
      final other = DateTime(y, 3, 5, 9).toIso8601String();
      expect(
        _row(en, 'deadline_changed', payload: {'newEndAt': other}).headline,
        'Anna moved the deadline to 5 Mar $y, 09:00',
      );
      expect(
        _row(ru, 'deadline_changed', payload: {'newEndAt': other}).headline,
        'Anna: новый срок — 5 марта $y, 09:00',
      );
    });
  });

  group('dates never show a raw timestamp', () {
    final year = DateTime.now().year;
    final iso = DateTime(year, 11, 21, 18).toIso8601String();
    for (final l10n in [en, ru]) {
      for (final (key, payload) in <(String, Map<String, Object?>)>[
        ('deadline_changed', {'newEndAt': iso}),
        ('deadline_reminder', {'newEndAt': iso}),
        ('request_stale', {'staleReason': 'deadlinePassed', 'endAt': iso}),
      ]) {
        test('${l10n.localeName} $key', () {
          final c = _row(l10n, key, payload: payload);
          _expectNoRawIso(c);
          expect(_all(c), contains('21'));
        });
      }
    }
    test(
      'deadline rows without an actor still show the date, no artifacts',
      () {
        for (final l10n in [en, ru]) {
          for (final key in ['deadline_changed', 'deadline_reminder']) {
            final c = _row(l10n, key, payload: {'newEndAt': iso}, actor: null);
            _expectNoNameArtifacts(c);
            _expectNoRawIso(c);
            expect(
              _all(c),
              contains(
                l10n.localeName == 'ru' ? '21 ноября, 18:00' : '21 Nov, 18:00',
              ),
            );
          }
        }
      },
    );
  });

  group('room message', () {
    test('body is the excerpt without the Request title', () {
      final c = _row(
        en,
        'room_message_posted',
        payload: {'excerpt': 'Bring a ladder'},
      );
      expect(c.body, 'Bring a ladder');
      expect(c.body, isNot(contains('Fix the roof')));
    });
    test('no excerpt reads as a sent message', () {
      expect(
        _row(en, 'room_message_posted', payload: {'excerpt': ''}).body,
        'Anna sent a message',
      );
      expect(
        _row(ru, 'room_message_posted', payload: {'excerpt': ''}).body,
        'Anna: новое сообщение',
      );
    });
  });

  group('Post identity', () {
    test('first response names the Post and the actor', () {
      final e = _row(
        en,
        'post_first_response',
        isPost: true,
        postRootExcerpt: 'Free apples in the yard',
      );
      final r = _row(
        ru,
        'post_first_response',
        isPost: true,
        postRootExcerpt: 'Free apples in the yard',
      );
      expect(e.headline, 'Anna replied to your post');
      expect(_all(e), contains('Post: Free apples in the yard'));
      expect(r.headline, 'Anna отвечает на ваш пост');
      expect(_all(r), contains('Пост: Free apples in the yard'));
    });
    test('a long root text is cut to 40 graphemes with an ellipsis', () {
      // Each family emoji is one grapheme but several UTF-16 code units.
      final root = List.filled(60, '👨‍👩‍👧').join();
      final c = _row(
        en,
        'post_first_response',
        isPost: true,
        postRootExcerpt: root,
      );
      final label = RegExp('Post: (.*)').firstMatch(_all(c))?.group(1)?.trim();
      expect(label, isNotNull);
      expect(Characters(label!).length, lessThanOrEqualTo(40));
      expect(label, endsWith('…'));
      expect(Characters(label).length, greaterThan(30));
    });
    test('an empty root text falls back to Post · author', () {
      expect(
        _all(
          _row(en, 'post_first_response', isPost: true, postRootExcerpt: ''),
        ),
        contains('Post · Anna'),
      );
      expect(
        _all(
          _row(ru, 'post_first_response', isPost: true, postRootExcerpt: ''),
        ),
        contains('Пост · Anna'),
      );
    });
    test('expiring post says hours left and how to keep it', () {
      final at = DateTime.now()
          .add(const Duration(hours: 3, minutes: 5))
          .toUtc()
          .toIso8601String();
      final e = _row(
        en,
        'post_expiring_soon',
        isPost: true,
        postRootExcerpt: 'Free apples',
        payload: {'expiresAt': at},
      );
      final r = _row(
        ru,
        'post_expiring_soon',
        isPost: true,
        postRootExcerpt: 'Free apples',
        payload: {'expiresAt': at},
      );
      expect(e.headline, 'Your post expires soon');
      expect(
        e.body,
        contains('Expires in 3 h. Turn it into a request to keep it going'),
      );
      expect(_all(e), contains('Post: Free apples'));
      expect(_all(r), contains('Пост: Free apples'));
      expect(r.headline, 'Ваш пост скоро исчезнет');
      expect(
        r.body,
        contains('Исчезнет через 3 ч. Оформите запрос, чтобы продолжить'),
      );
    });
  });

  group('closure and stale', () {
    test('closure_opened', () {
      final e = _row(en, 'closure_opened');
      expect(e.headline, 'Time to sum up');
      expect(e.body, 'Closing is open: mark who helped');
      final r = _row(ru, 'closure_opened');
      expect(r.headline, 'Пора подвести итоги');
      expect(r.body, 'Подведение итогов открыто: отметьте, кто помог');
    });
    test('closure_draft_reminder', () {
      final e = _row(en, 'closure_draft_reminder');
      expect(e.headline, 'Finish your review');
      expect(e.body, "Your review isn't sent yet; closing ends within a day");
      expect(
        _row(ru, 'closure_draft_reminder').body,
        'Ваша оценка ещё не отправлена; итоги закроются в течение суток',
      );
    });
    test('closure_finalized', () {
      expect(
        _all(_row(en, 'closure_finalized')),
        'Request closed\nThe results are in',
      );
      expect(
        _all(_row(ru, 'closure_finalized')),
        'Запрос закрыт\nИтоги подведены',
      );
    });
    test('closure_cancelled without an actor shows no name artifacts', () {
      _expectNoNameArtifacts(_row(en, 'closure_cancelled', actor: null));
      _expectNoNameArtifacts(_row(ru, 'closure_cancelled', actor: null));
    });
    test('closure_cancelled with and without actor', () {
      expect(
        _all(_row(en, 'closure_cancelled')),
        contains('Anna cancelled the closing'),
      );
      expect(
        _all(_row(ru, 'closure_cancelled')),
        contains('Anna отменил(а) подведение итогов'),
      );
      expect(
        _all(_row(en, 'closure_cancelled', actor: null)),
        contains('Closing was cancelled'),
      );
      expect(
        _all(_row(ru, 'closure_cancelled', actor: null)),
        contains('Подведение итогов отменено'),
      );
    });
    test('stale quiet', () {
      final p = {'staleReason': 'quiet', 'quietDays': 5};
      expect(
        _all(_row(en, 'request_stale', payload: p)),
        contains(
          'No activity for 5 days. Close it, extend it or post an update',
        ),
      );
      expect(
        _all(_row(ru, 'request_stale', payload: p)),
        contains(
          '5 дней без движения. Закройте, продлите или напишите новости',
        ),
      );
    });
    test('RU plural forms of days', () {
      const forms = {1: 'день', 2: 'дня', 5: 'дней', 21: 'день'};
      forms.forEach((n, word) {
        expect(
          _all(
            _row(
              ru,
              'request_stale',
              payload: {'staleReason': 'quiet', 'quietDays': n},
            ),
          ),
          contains('$n $word без движения'),
        );
      });
    });
    test('stale deadline passed', () {
      final p = {
        'staleReason': 'deadlinePassed',
        'endAt': DateTime(DateTime.now().year, 11, 21, 12).toIso8601String(),
      };
      expect(
        _all(_row(en, 'request_stale', payload: p)),
        contains('The deadline passed on 21 Nov. Close it or extend it'),
      );
      expect(
        _all(_row(ru, 'request_stale', payload: p)),
        contains('Срок прошёл 21 ноября. Закройте или продлите запрос'),
      );
    });
  });

  group('trust rows name the person', () {
    const wording = {
      'trust_given_changed_up': (
        'You trust Anna more',
        'Anna: вы доверяете больше',
      ),
      'trust_given_changed_down': (
        'You trust Anna less',
        'Anna: вы доверяете меньше',
      ),
      'trust_given_changed_neutral': (
        'Your trust in Anna did not change',
        'Anna: ваше доверие не изменилось',
      ),
      'trust_received_changed_up': (
        'Anna trusts you more',
        'Anna доверяет вам больше',
      ),
      'trust_received_changed_down': (
        'Anna trusts you less',
        'Anna доверяет вам меньше',
      ),
      'trust_received_changed_neutral': (
        'Anna reviewed you, trust unchanged',
        'Anna оценил(а) вас, доверие не изменилось',
      ),
    };
    wording.forEach((key, texts) {
      test('$key says the name in EN and RU', () {
        expect(_row(en, key).headline, texts.$1);
        expect(_row(ru, key).headline, texts.$2);
      });
      test('$key: no EN row says "them", headline or body', () {
        expect(_all(_row(en, key)), isNot(contains('them')));
        expect(
          _all(_row(en, key, body: 'Fix the roof — trust shifted')),
          isNot(contains('them')),
        );
      });
      test('$key without an actor shows no name artifacts', () {
        _expectNoNameArtifacts(_row(en, key, actor: null));
        _expectNoNameArtifacts(_row(ru, key, actor: null));
      });
    });
  });
}
