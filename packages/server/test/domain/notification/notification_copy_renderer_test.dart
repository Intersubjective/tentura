import 'package:characters/characters.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';
import 'package:tentura_server/domain/notification/invite_accepted_copy.dart';

// One RU/EN copy table for every presentation key
// (docs/plans/notification-identity-spec.md §4–§5.2, §8): exact strings,
// access-gated labels and actor names, Russian everywhere, and localized
// lock-screen-safe copy.

final _now = DateTime.utc(2026, 11, 16, 9);
final _cyrillic = RegExp('[А-Яа-яЁё]');
final _latinWord = RegExp('[A-Za-z]{2,}');
final _isoTimestamp = RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');

const _hiddenTitle = 'SECRET-TITLE-Ж';
const _hiddenActor = 'SECRET-ACTOR-Ж';

String _snake(String camel) => camel.replaceAllMapped(
  RegExp('[A-Z]'),
  (m) => '_${m[0]!.toLowerCase()}',
);

/// Every presentation key a receipt can carry: one per [AttentionEventType]
/// plus the bookmark-only closure variant.
final _allKeys = <String>[
  for (final type in AttentionEventType.values) _snake(type.name),
  'closure_opened_bookmark_only',
];

const _declaredNeverWritten = <String>[
  'needs_me',
  'blocker_opened',
  'blocker_resolved',
  'promise_made',
  'promise_withdrawn',
  'stale_reminder',
  'obligation_ended',
  'commitment_accepted',
  'commitment_resolved',
  'commitment_cancelled',
  'commitment_redirected',
];

NotificationIdentity _identity({
  NotificationEntityKind entityKind = NotificationEntityKind.request,
  String? label = 'Fix the roof',
  bool tombstone = false,
  bool readable = true,
  String? actorName = 'Anna',
  bool actorHidden = false,
  String? relatedLabel,
  bool expired = false,
  bool hasImage = false,
}) => NotificationIdentity(
  entityKind: entityKind,
  label: label,
  tombstone: tombstone,
  readable: readable,
  actorName: actorName,
  actorHidden: actorHidden,
  relatedLabel: relatedLabel,
  expired: expired,
  hasImage: hasImage,
);

/// Facts rich enough for every key to pick its main variant.
Map<String, Object?> _richFacts() => {
  'beaconId': 'beacon-1',
  'actorUserId': 'actor-1',
  'excerpt': 'hello',
  'toStatus': 'closed',
  'fromStatus': 'open',
  'direction': 'child',
  'relatedBeaconId': 'beacon-2',
  'newEndAt': '2026-11-21T15:00:00Z',
  'endAt': '2026-11-21T15:00:00Z',
  'expiresAt': '2026-11-16T12:00:00Z',
  'staleReason': 'quiet',
  'quietDays': 5,
  'relativeMinutes': 15,
  'isBackupOffer': false,
  'helperId': 'helper-1',
  'done': false,
  'path': [
    {'userId': 'user-b', 'displayName': 'Boris', 'anonymousCount': 0},
  ],
};

NotificationCopy _render(
  String key, {
  NotificationIdentity? identity,
  Map<String, Object?>? facts,
  String locale = 'en',
  NotificationKind? kind,
  int tzOffsetMinutes = 0,
}) => const NotificationCopyRenderer().render(
  presentationKey: key,
  kind: kind,
  facts: facts ?? const {},
  identity: identity ?? _identity(),
  locale: locale,
  tzOffsetMinutes: tzOffsetMinutes,
  now: _now,
);

List<String> _fields(NotificationCopy copy) => [
  copy.headline,
  copy.sentence,
  ?copy.excerpt,
  ?copy.entityLabel,
];

void main() {
  group('help offer copy', () {
    test('English names the Request, the headline and the helper', () {
      final copy = _render('help_offer_submitted');
      expect(copy.entityLabel, 'Fix the roof');
      expect(copy.headline, 'Help offered');
      expect(copy.sentence, 'Anna offered help');
    });

    test('Russian locales render Russian copy', () {
      final copy = _render('help_offer_submitted', locale: 'ru-RU');
      expect(copy.entityLabel, 'Fix the roof');
      expect(copy.headline, 'Предложена помощь');
      expect(copy.sentence, 'Anna предлагает помощь');
    });

    test('non-Russian locales fall back to English', () {
      final copy = _render('help_offer_submitted', locale: 'de');
      expect(copy.headline, 'Help offered');
      expect(copy.sentence, 'Anna offered help');
    });

    test('a backup offer says so in both locales', () {
      const facts = {'isBackupOffer': true};
      expect(
        _render('help_offer_submitted', facts: facts).sentence,
        'Anna offered to help as backup',
      );
      expect(
        _render('help_offer_submitted', facts: facts, locale: 'ru').sentence,
        'Anna предлагает помощь как запасной вариант',
      );
    });

    for (final name in [null, '']) {
      test('an actor without a name (${name == null ? 'null' : 'empty'}) '
          'reads as Someone', () {
        final identity = _identity(actorName: name);
        expect(
          _render('help_offer_submitted', identity: identity).sentence,
          'Someone offered help',
        );
        expect(
          _render(
            'help_offer_submitted',
            identity: identity,
            locale: 'ru',
          ).sentence,
          'Кто-то предлагает помощь',
        );
      });
    }
  });

  group('an entity the recipient cannot read', () {
    final identity = _identity(readable: false, label: _hiddenTitle);

    test('offer declined has no label and a label-free sentence', () {
      final en = _render('offer_declined', identity: identity);
      expect(en.entityLabel, isNull);
      expect(en.headline, 'Offer declined');
      expect(en.sentence, 'Anna declined your offer');

      final ru = _render('offer_declined', identity: identity, locale: 'ru');
      expect(ru.entityLabel, isNull);
      expect(ru.headline, 'Предложение отклонено');
      expect(ru.sentence, 'Anna отклонил(а) ваше предложение');

      for (final field in [..._fields(en), ..._fields(ru)]) {
        expect(field, isNot(contains(_hiddenTitle)));
      }
    });
  });

  group('entity labels', () {
    test('a Post with root text is labelled with that text', () {
      final identity = _identity(
        entityKind: NotificationEntityKind.post,
        label: 'Need a ladder',
      );
      expect(
        _render('relay_received', identity: identity).entityLabel,
        'Post: Need a ladder',
      );
      expect(
        _render('relay_received', identity: identity, locale: 'ru').entityLabel,
        'Пост: Need a ladder',
      );
    });

    test('a Post with only a photo is labelled as a photo post', () {
      final identity = _identity(
        entityKind: NotificationEntityKind.post,
        label: null,
        hasImage: true,
      );
      expect(
        _render('relay_received', identity: identity).entityLabel,
        'Post with a photo',
      );
      expect(
        _render('relay_received', identity: identity, locale: 'ru').entityLabel,
        'Пост с фото',
      );
    });

    test('a long Post root text is cut to 40 graphemes with an ellipsis', () {
      final rootText = List.filled(12, 'ladder').join(' '); // 83 graphemes
      final identity = _identity(
        entityKind: NotificationEntityKind.post,
        label: rootText,
      );
      final label = _render('relay_received', identity: identity).entityLabel!;
      expect(label, startsWith('Post: '));
      final text = label.substring('Post: '.length);
      expect(text.characters.length, lessThanOrEqualTo(40));
      expect(text, endsWith('…'));
      expect(rootText, startsWith(text.substring(0, text.length - 1).trim()));
    });

    test('deleted entities with a readable tombstone are named as deleted', () {
      for (final (kind, en, ru) in [
        (NotificationEntityKind.request, 'Deleted request', 'Удалённый запрос'),
        (NotificationEntityKind.post, 'Deleted post', 'Удалённый пост'),
      ]) {
        final identity = _identity(
          entityKind: kind,
          label: _hiddenTitle,
          readable: false,
          tombstone: true,
        );
        final enCopy = _render('relay_received', identity: identity);
        final ruCopy = _render(
          'relay_received',
          identity: identity,
          locale: 'ru',
        );
        expect(enCopy.entityLabel, en);
        expect(ruCopy.entityLabel, ru);
        for (final field in [..._fields(enCopy), ..._fields(ruCopy)]) {
          expect(field, isNot(contains(_hiddenTitle)));
        }
      }
    });
  });

  group('deadline changes', () {
    test('a new deadline is a formatted local date, never ISO', () {
      const facts = {'newEndAt': '2026-11-21T15:00:00Z'};
      final en = _render(
        'deadline_changed',
        facts: facts,
        tzOffsetMinutes: 180,
      );
      final ru = _render(
        'deadline_changed',
        facts: facts,
        tzOffsetMinutes: 180,
        locale: 'ru',
      );
      expect(en.sentence, 'Anna moved the deadline to 21 Nov, 18:00');
      expect(ru.sentence, 'Anna: новый срок — 21 ноября, 18:00');
      for (final field in [..._fields(en), ..._fields(ru)]) {
        expect(field, isNot(matches(_isoTimestamp)));
      }
    });

    test('a removed deadline says it was removed', () {
      const facts = {'newEndAt': null};
      expect(
        _render('deadline_changed', facts: facts).sentence,
        'Anna removed the deadline',
      );
      expect(
        _render('deadline_changed', facts: facts, locale: 'ru').sentence,
        'Anna убрал(а) срок',
      );
    });
  });

  group('status changes', () {
    test('the new status is a localized word, not the enum name', () {
      const facts = {'fromStatus': 'open', 'toStatus': 'closed'};
      final en = _render('request_status_changed', facts: facts);
      final ru = _render('request_status_changed', facts: facts, locale: 'ru');
      expect(en.sentence, 'Anna changed the status to «Closed»');
      expect(ru.sentence, 'Anna: статус «Закрыт»');
      for (final sentence in [en.sentence, ru.sentence]) {
        expect(sentence, isNot(contains('open')));
        expect(sentence, isNot(contains('closed')));
      }
    });

    test('a linked Request is named when its label is readable', () {
      const facts = {'toStatus': 'closed', 'relatedBeaconId': 'beacon-2'};
      final identity = _identity(relatedLabel: 'Buy paint');
      expect(
        _render(
          'beacon_hierarchy_status_changed',
          facts: facts,
          identity: identity,
        ).sentence,
        'Linked request «Buy paint» was closed',
      );
      expect(
        _render(
          'beacon_hierarchy_status_changed',
          facts: facts,
          identity: identity,
          locale: 'ru',
        ).sentence,
        'Связанный запрос «Buy paint» закрыт',
      );
    });

    test('an unreadable linked Request is not named', () {
      const facts = {'toStatus': 'closed', 'relatedBeaconId': 'beacon-2'};
      expect(
        _render('beacon_hierarchy_status_changed', facts: facts).sentence,
        'A linked request was closed',
      );
      expect(
        _render(
          'beacon_hierarchy_status_changed',
          facts: facts,
          locale: 'ru',
        ).sentence,
        'Связанный запрос закрыт',
      );
    });
  });

  group('a quiet or overdue Request', () {
    test('quiet days use Russian plural forms', () {
      for (final (days, words) in [
        (1, '1 день без движения'),
        (2, '2 дня без движения'),
        (5, '5 дней без движения'),
        (11, '11 дней без движения'),
        (21, '21 день без движения'),
        (22, '22 дня без движения'),
        (25, '25 дней без движения'),
      ]) {
        final sentence = _render(
          'request_stale',
          facts: {'staleReason': 'quiet', 'quietDays': days},
          locale: 'ru',
        ).sentence;
        expect(sentence, startsWith(words));
        expect(sentence, contains('Закройте, продлите или напишите новости'));
      }
    });

    test('quiet days in English', () {
      expect(
        _render(
          'request_stale',
          facts: {'staleReason': 'quiet', 'quietDays': 5},
        ).sentence,
        startsWith('No activity for 5 days'),
      );
      expect(
        _render(
          'request_stale',
          facts: {'staleReason': 'quiet', 'quietDays': 1},
        ).sentence,
        startsWith('No activity for 1 day'),
      );
    });

    test('a passed deadline names the formatted date', () {
      const facts = {
        'staleReason': 'deadlinePassed',
        'endAt': '2026-11-21T15:00:00Z',
      };
      expect(
        _render('request_stale', facts: facts, tzOffsetMinutes: 180).sentence,
        'The deadline passed on 21 Nov, 18:00. Close it or extend it',
      );
      expect(
        _render(
          'request_stale',
          facts: facts,
          tzOffsetMinutes: 180,
          locale: 'ru',
        ).sentence,
        'Срок прошёл 21 ноября, 18:00. Закройте или продлите запрос',
      );
    });
  });

  group('room messages', () {
    test('a discussion message quotes the message', () {
      final copy = _render(
        'room_message_posted',
        facts: {'excerpt': 'hello'},
        kind: NotificationKind.roomActivityLowPriority,
      );
      expect(copy.sentence, 'Anna: hello');
    });

    test('a Questions message never carries its text', () {
      const facts = {
        'excerpt': 'private-question-text',
        'coordinationItemId': 'q-1',
      };
      final en = _render(
        'room_message_posted',
        facts: facts,
        kind: NotificationKind.roomActivityLowPriority,
      );
      final ru = _render(
        'room_message_posted',
        facts: facts,
        kind: NotificationKind.roomActivityLowPriority,
        locale: 'ru',
      );
      expect(en.sentence, 'Anna wrote in Questions');
      expect(ru.sentence, 'Anna пишет в вопросах');
      for (final field in [..._fields(en), ..._fields(ru)]) {
        expect(field, isNot(contains('private-question-text')));
      }
    });

    test('a mention names the actor and quotes the message', () {
      const facts = {'excerpt': 'hello'};
      expect(
        _render(
          'room_message_posted',
          facts: facts,
          kind: NotificationKind.roomMention,
        ).sentence,
        'Anna mentioned you: hello',
      );
      expect(
        _render(
          'room_message_posted',
          facts: facts,
          kind: NotificationKind.roomMention,
          locale: 'ru',
        ).sentence,
        'Anna упоминает вас: hello',
      );
    });
  });

  group('keys declared but never written', () {
    for (final key in _declaredNeverWritten) {
      test('$key renders «actor · headline» in both locales', () {
        for (final locale in ['en', 'ru']) {
          final copy = _render(key, locale: locale);
          expect(copy.headline, isNotEmpty, reason: '$key $locale');
          expect(copy.sentence, 'Anna · ${copy.headline}', reason: locale);
        }
      });
    }
  });

  group('copy table: exact headline and sentence per key and variant', () {
    for (final row in _table) {
      if (row.en == null) continue;
      test(row.name, () {
        for (final (locale, expected) in [('en', row.en!), ('ru', row.ru!)]) {
          final copy = row.render(locale);
          expect(copy.headline, expected.$1, reason: '${row.name} $locale');
          expect(copy.sentence, expected.$2, reason: '${row.name} $locale');
        }
      });
    }

    test('the table and the key list carry the baton-together keys', () {
      for (final key in ['baton_partner_asked', 'baton_partner_answered']) {
        expect(_allKeys, contains(key));
        expect(_table.map((row) => row.key), contains(key));
      }
    });

    test('the table covers every presentation key', () {
      expect(_table.map((row) => row.key).toSet(), containsAll(_allKeys));
    });
  });

  group('every presentation key has copy', () {
    final identities = {
      'readable': _identity(relatedLabel: 'Buy paint'),
      'unreadable': _identity(readable: false),
      'tombstone': _identity(readable: false, tombstone: true),
    };
    for (final key in _allKeys) {
      test('$key renders a headline and a sentence', () {
        for (final locale in ['en', 'ru']) {
          for (final MapEntry(key: variant, value: identity)
              in identities.entries) {
            final copy = _render(
              key,
              identity: identity,
              facts: _richFacts(),
              locale: locale,
            );
            final why = '$key $locale $variant';
            expect(copy.headline.trim(), isNotEmpty, reason: why);
            expect(copy.sentence.trim(), isNotEmpty, reason: why);
          }
        }
      });
    }
  });

  group('hidden titles and actors never leak', () {
    for (final row in _table) {
      test('${row.name} keeps an unreadable title and a hidden actor out', () {
        for (final locale in ['en', 'ru']) {
          final hiddenTitle = row.render(
            locale,
            identity: row.identity.copy(readable: false, label: _hiddenTitle),
          );
          final hiddenActor = row.render(
            locale,
            identity: row.identity.copy(
              actorName: _hiddenActor,
              actorHidden: true,
            ),
          );
          for (final field in _fields(hiddenTitle)) {
            expect(field, isNot(contains(_hiddenTitle)), reason: locale);
          }
          for (final field in _fields(hiddenActor)) {
            expect(field, isNot(contains(_hiddenActor)), reason: locale);
          }
        }
      });
    }
  });

  group('no output carries a raw ISO timestamp', () {
    for (final row in _table) {
      test(row.name, () {
        for (final locale in ['en', 'ru']) {
          for (final facts in [
            row.facts,
            {..._richFacts(), ...row.facts},
          ]) {
            final copy = row.render(locale, facts: facts);
            for (final field in _fields(copy)) {
              expect(field, isNot(matches(_isoTimestamp)), reason: locale);
            }
          }
        }
      });
    }
  });

  group('Russian copy is Russian', () {
    /// The renderer's own words: names, labels and user text removed.
    String own(String text) {
      var out = text;
      for (final word in [
        'Fix the roof',
        'Buy paint',
        'Need a ladder',
        'hello',
        'Paint',
        'Anna',
        'Boris',
        'Tentura',
      ]) {
        out = out.replaceAll(word, '');
      }
      return out.trim();
    }

    for (final row in _table) {
      test(row.name, () {
        final copy = row.render('ru');
        final parts = [
          ('headline', copy.headline),
          // `Anna: hello` is the actor and the user's words only.
          if (!row.ruSentenceIsUserWords) ('sentence', copy.sentence),
        ];
        for (final (part, text) in parts) {
          final words = own(text);
          expect(words, matches(_cyrillic), reason: '${row.name} $part: $text');
          expect(
            words,
            isNot(matches(_latinWord)),
            reason: '${row.name} $part: $text',
          );
        }
      });
    }

    test('a discussion message has only the actor and the words', () {
      final row = _table.firstWhere((r) => r.ruSentenceIsUserWords);
      expect(row.render('ru').sentence, 'Anna: hello');
    });
  });

  group('lock-screen-safe copy', () {
    const enBodies = {
      NotificationCategory.asksOfMe: 'Something needs your response',
      NotificationCategory.unblocksMe: 'An update is ready for you',
      NotificationCategory.coordination: 'New activity in a request thread',
      NotificationCategory.connections: 'New connection activity',
      NotificationCategory.ambient: 'New activity',
      NotificationCategory.postsSharedWithMe: 'A post was shared with you',
    };
    const renderer = NotificationCopyRenderer();

    for (final category in NotificationCategory.values) {
      test('${category.name} is generic and localized', () {
        final en = renderer.lockScreenSafe(category, 'en');
        final ru = renderer.lockScreenSafe(category, 'ru');
        expect(en.title, isNotEmpty);
        expect(ru.title, isNotEmpty);
        expect(en.body, enBodies[category]);
        expect(ru.body, isNotEmpty);
        expect(ru.body, isNot(en.body));
        expect(ru.body, matches(_cyrillic));
      });
    }
  });
}

extension on NotificationIdentity {
  NotificationIdentity copy({
    bool? readable,
    String? label,
    String? actorName,
    bool? actorHidden,
  }) => NotificationIdentity(
    entityKind: entityKind,
    label: label ?? this.label,
    tombstone: tombstone,
    readable: readable ?? this.readable,
    actorName: actorName ?? this.actorName,
    actorHidden: actorHidden ?? this.actorHidden,
    relatedLabel: relatedLabel,
    expired: expired,
    hasImage: hasImage,
  );
}

/// One §5.2 variant: the inputs and the exact EN/RU (headline, sentence).
class _Row {
  _Row(
    this.name,
    this.key, {
    this.en,
    this.ru,
    Map<String, Object?> facts = const {},
    this.kind,
    NotificationIdentity? identity,
    this.tzOffsetMinutes = 0,
    this.ruSentenceIsUserWords = false,
    bool withActor = true,
  }) : facts = {
         'beaconId': 'beacon-1',
         if (withActor) 'actorUserId': 'actor-1',
         ...facts,
       },
       identity = identity ?? _identity();

  final String name;
  final String key;
  final (String, String)? en;
  final (String, String)? ru;
  final Map<String, Object?> facts;
  final NotificationKind? kind;
  final NotificationIdentity identity;
  final int tzOffsetMinutes;
  final bool ruSentenceIsUserWords;

  NotificationCopy render(
    String locale, {
    NotificationIdentity? identity,
    Map<String, Object?>? facts,
  }) => _render(
    key,
    identity: identity ?? this.identity,
    facts: facts ?? this.facts,
    kind: kind,
    locale: locale,
    tzOffsetMinutes: tzOffsetMinutes,
  );
}

final _post = _identity(
  entityKind: NotificationEntityKind.post,
  label: 'Need a ladder',
);
const _step = {'excerpt': 'Paint'};
const _date = {'newEndAt': '2026-11-21T15:00:00Z'};

final _table = <_Row>[
  _Row(
    'relay_received about a Request',
    'relay_received',
    kind: NotificationKind.newRelay,
    en: ('Request forwarded', 'Anna forwarded you a request'),
    ru: ('Запрос переслан', 'Anna пересылает вам запрос'),
  ),
  _Row(
    'relay_received about a Post',
    'relay_received',
    kind: NotificationKind.newRelay,
    facts: {'beaconKind': 'post'},
    identity: _post,
    en: ('Post shared', 'Anna shared a post with you'),
    ru: ('Поделились постом', 'Anna делится с вами постом'),
  ),
  _Row(
    'help_offer_submitted',
    'help_offer_submitted',
    kind: NotificationKind.commitmentEvent,
    en: ('Help offered', 'Anna offered help'),
    ru: ('Предложена помощь', 'Anna предлагает помощь'),
  ),
  _Row(
    'help_offer_submitted as backup',
    'help_offer_submitted',
    kind: NotificationKind.commitmentEvent,
    facts: {'isBackupOffer': true},
    en: ('Help offered', 'Anna offered to help as backup'),
    ru: ('Предложена помощь', 'Anna предлагает помощь как запасной вариант'),
  ),
  _Row(
    'help_withdrawn',
    'help_withdrawn',
    en: ('Help offer withdrawn', 'Anna withdrew their help offer'),
    ru: ('Предложение помощи отозвано', 'Anna отозвал(а) предложение помощи'),
  ),
  // The reason key is localized with the client's words for it
  // (`withdrawCantDoIt` in app_en.arb / app_ru.arb, spec N5), never raw.
  _Row(
    'help_withdrawn with a reason',
    'help_withdrawn',
    facts: {'withdrawReason': 'cannot_do_it'},
    en: (
      'Help offer withdrawn',
      'Anna withdrew their help offer (Cannot do it anymore)',
    ),
    ru: (
      'Предложение помощи отозвано',
      'Anna отозвал(а) предложение помощи (Больше не могу)',
    ),
  ),
  _Row(
    'forward_declined',
    'forward_declined',
    en: ("Can't help", "Anna can't help"),
    ru: ('Не может помочь', 'Anna не может помочь'),
  ),
  _Row(
    'offer_accepted',
    'offer_accepted',
    kind: NotificationKind.roomAccess,
    en: ('Offer accepted', 'Anna accepted your offer'),
    ru: ('Предложение принято', 'Anna принял(а) ваше предложение'),
  ),
  _Row(
    'offer_declined',
    'offer_declined',
    kind: NotificationKind.commitmentDeclined,
    en: ('Offer declined', 'Anna declined your offer'),
    ru: ('Предложение отклонено', 'Anna отклонил(а) ваше предложение'),
  ),
  _Row(
    'offer_removed',
    'offer_removed',
    kind: NotificationKind.commitmentRemoved,
    en: ('Removed from the discussion', 'Anna removed you from the discussion'),
    ru: ('Вас убрали из обсуждения', 'Anna убрал(а) вас из обсуждения'),
  ),
  _Row(
    'commitment_released',
    'commitment_released',
    kind: NotificationKind.commitmentReleased,
    en: ('Participation ended', 'Anna ended your participation'),
    ru: ('Участие завершено', 'Anna завершил(а) ваше участие'),
  ),
  _Row(
    'room_message_posted in the discussion',
    'room_message_posted',
    kind: NotificationKind.roomActivityLowPriority,
    facts: {'excerpt': 'hello'},
    ruSentenceIsUserWords: true,
    en: ('New message', 'Anna: hello'),
    ru: ('Новое сообщение', 'Anna: hello'),
  ),
  _Row(
    'room_message_posted in the discussion without text',
    'room_message_posted',
    kind: NotificationKind.roomActivityLowPriority,
    facts: {'excerpt': ''},
    en: ('New message', 'Anna sent a message'),
    ru: ('Новое сообщение', 'Anna: новое сообщение'),
  ),
  _Row(
    'room_message_posted in Questions',
    'room_message_posted',
    kind: NotificationKind.roomActivityLowPriority,
    facts: {'excerpt': 'hello', 'coordinationItemId': 'q-1'},
    en: ('New message in Questions', 'Anna wrote in Questions'),
    ru: ('Новое сообщение в вопросах', 'Anna пишет в вопросах'),
  ),
  _Row(
    'room_message_posted as a mention',
    'room_message_posted',
    kind: NotificationKind.roomMention,
    facts: {'excerpt': 'hello'},
    en: ('You were mentioned', 'Anna mentioned you: hello'),
    ru: ('Вас упомянули', 'Anna упоминает вас: hello'),
  ),
  _Row(
    'post_first_response',
    'post_first_response',
    kind: NotificationKind.postFirstResponse,
    identity: _post,
    en: ('Reply to your post', 'Anna replied to your post'),
    ru: ('Ответ на ваш пост', 'Anna отвечает на ваш пост'),
  ),
  _Row(
    'post_first_response with the reply text',
    'post_first_response',
    kind: NotificationKind.postFirstResponse,
    identity: _post,
    facts: {'excerpt': 'hello'},
    en: ('Reply to your post', 'Anna replied to your post: hello'),
    ru: ('Ответ на ваш пост', 'Anna отвечает на ваш пост: hello'),
  ),
  _Row(
    'post_expiring_soon',
    'post_expiring_soon',
    kind: NotificationKind.postExpiringSoon,
    identity: _post,
    withActor: false,
    facts: {'expiresAt': '2026-11-16T12:00:00Z'},
    en: (
      'Your post expires soon',
      'Expires in 3 h. Turn it into a request to keep it going',
    ),
    ru: (
      'Ваш пост скоро исчезнет',
      'Исчезнет через 3 ч. Оформите запрос, чтобы продолжить',
    ),
  ),
  _Row(
    'Request created from a Post',
    'post_request_created',
    kind: NotificationKind.coordinationChanged,
    withActor: false,
    en: ('Request created', 'You created a request from a post'),
    ru: ('Запрос создан', 'Вы создали запрос из поста'),
  ),
  _Row(
    'request_status_changed',
    'request_status_changed',
    facts: {'fromStatus': 'open', 'toStatus': 'closed'},
    en: ('Status changed', 'Anna changed the status to «Closed»'),
    ru: ('Статус изменён', 'Anna: статус «Закрыт»'),
  ),
  for (final (status, en, ru) in [
    ('closed', 'was closed', 'закрыт'),
    ('cancelled', 'was cancelled', 'отменён'),
    ('reviewOpen', 'entered Final check', 'на подведении итогов'),
    ('deleted', 'was deleted', 'удалён'),
  ]) ...[
    _Row(
      'beacon_hierarchy_status_changed to $status, readable linked Request',
      'beacon_hierarchy_status_changed',
      withActor: false,
      facts: {
        'toStatus': status,
        'relatedBeaconId': 'beacon-2',
        'direction': 'child',
      },
      identity: _identity(relatedLabel: 'Buy paint'),
      en: ('Linked request updated', 'Linked request «Buy paint» $en'),
      ru: ('Связанный запрос изменён', 'Связанный запрос «Buy paint» $ru'),
    ),
    _Row(
      'beacon_hierarchy_status_changed to $status, unreadable linked Request',
      'beacon_hierarchy_status_changed',
      withActor: false,
      facts: {
        'toStatus': status,
        'relatedBeaconId': 'beacon-2',
        'direction': 'child',
      },
      en: ('Linked request updated', 'A linked request $en'),
      ru: ('Связанный запрос изменён', 'Связанный запрос $ru'),
    ),
  ],
  _Row(
    'deadline_changed to a date',
    'deadline_changed',
    kind: NotificationKind.deadlineChanged,
    facts: _date,
    tzOffsetMinutes: 180,
    en: ('Deadline changed', 'Anna moved the deadline to 21 Nov, 18:00'),
    ru: ('Срок изменён', 'Anna: новый срок — 21 ноября, 18:00'),
  ),
  _Row(
    'deadline_changed removed',
    'deadline_changed',
    kind: NotificationKind.deadlineChanged,
    facts: {'newEndAt': null},
    en: ('Deadline changed', 'Anna removed the deadline'),
    ru: ('Срок изменён', 'Anna убрал(а) срок'),
  ),
  _Row(
    'deadline_reminder',
    'deadline_reminder',
    kind: NotificationKind.deadlineReminder,
    withActor: false,
    facts: _date,
    tzOffsetMinutes: 180,
    en: ('Deadline tomorrow', 'Deadline: 21 Nov, 18:00'),
    ru: ('Срок завтра', 'Срок: 21 ноября, 18:00'),
  ),
  _Row(
    'coordination_changed',
    'coordination_changed',
    kind: NotificationKind.coordinationChanged,
    facts: {'excerpt': 'hello'},
    en: ('Coordination changed', 'Anna updated the coordination: hello'),
    ru: (
      'Договорённости изменились',
      'Anna: договорённости изменились — hello',
    ),
  ),
  _Row(
    'baton_asked',
    'baton_asked',
    kind: NotificationKind.batonAsked,
    facts: {'excerpt': 'hello'},
    en: ("Who'll take it?", 'Anna asks if you can help: hello'),
    ru: ('Кто возьмётся?', 'Anna спрашивает, сможете ли вы помочь: hello'),
  ),
  _Row(
    'baton_partner_asked',
    'baton_partner_asked',
    facts: {'excerpt': 'hello'},
    en: (
      'Take it on together?',
      'Anna wants to take it on together with you: hello',
    ),
    ru: ('Взяться вместе?', 'Anna предлагает взяться вместе: hello'),
  ),
  _Row(
    'baton_partner_answered accepted',
    'baton_partner_answered',
    facts: {'accepted': true, 'excerpt': 'hello'},
    en: ('Together', 'Anna will take it on with you: hello'),
    ru: ('Вместе', 'Anna возьмётся вместе с вами: hello'),
  ),
  _Row(
    'baton_partner_answered declined',
    'baton_partner_answered',
    facts: {'accepted': false, 'excerpt': 'hello'},
    en: ("Can't join", "Anna can't join you. Answer again: hello"),
    ru: (
      'Не сможет присоединиться',
      'Anna не сможет присоединиться. Ответьте ещё раз: hello',
    ),
  ),
  _Row(
    'baton_taken',
    'baton_taken',
    kind: NotificationKind.batonTaken,
    facts: {'excerpt': 'hello'},
    en: ('You took it', 'You took it: hello'),
    ru: ('Вы взялись', 'Вы взялись: hello'),
  ),
  _Row(
    'baton_all_answered',
    'baton_all_answered',
    kind: NotificationKind.batonAllAnswered,
    withActor: false,
    en: ('Everyone answered', "Everyone answered your «Who'll take it?»"),
    ru: ('Все ответили', 'Все ответили на ваше «Кто возьмётся?»'),
  ),
  _Row(
    'author_invite_received',
    'author_invite_received',
    kind: NotificationKind.authorInviteReceived,
    en: ('Invitation to help', 'Anna asks you to help'),
    ru: ('Приглашение помочь', 'Anna зовёт вас помочь'),
  ),
  _Row(
    'author_invite_received with a note',
    'author_invite_received',
    kind: NotificationKind.authorInviteReceived,
    facts: {'excerpt': 'hello'},
    en: ('Invitation to help', 'Anna asks you to help: hello'),
    ru: ('Приглашение помочь', 'Anna зовёт вас помочь: hello'),
  ),
  _Row(
    'author_invite_accepted',
    'author_invite_accepted',
    kind: NotificationKind.authorInviteAccepted,
    en: ('Invitation accepted', 'Anna accepted your invitation'),
    ru: ('Приглашение принято', 'Anna принял(а) ваше приглашение'),
  ),
  _Row(
    'author_invite_declined',
    'author_invite_declined',
    kind: NotificationKind.authorInviteDeclined,
    en: ("Can't make it", "Anna can't make it"),
    ru: ('Не сможет', 'Anna не сможет помочь'),
  ),
  _Row(
    'plan_step_due',
    'plan_step_due',
    kind: NotificationKind.planStepDue,
    withActor: false,
    facts: _step,
    en: ('Your step has started', 'Your step «Paint» has started'),
    ru: ('Ваш шаг начался', 'Ваш шаг «Paint» начался'),
  ),
  _Row(
    'plan_step_turn',
    'plan_step_turn',
    kind: NotificationKind.planStepTurn,
    withActor: false,
    facts: _step,
    en: ('Your turn', 'Your turn: «Paint»'),
    ru: ('Ваш ход', 'Ваш ход: «Paint»'),
  ),
  _Row(
    'plan_change_pending',
    'plan_change_pending',
    kind: NotificationKind.planChangePending,
    facts: _step,
    en: ('Your step changed', 'Anna changed your step «Paint»'),
    ru: ('Ваш шаг изменён', 'Anna изменил(а) ваш шаг «Paint»'),
  ),
  _Row(
    'plan_step_reminder',
    'plan_step_reminder',
    kind: NotificationKind.planStepReminder,
    withActor: false,
    facts: {..._step, 'relativeMinutes': 15},
    en: ('Step soon', 'Your step «Paint» starts in 15 min'),
    ru: ('Скоро ваш шаг', 'Ваш шаг «Paint» через 15 мин'),
  ),
  _Row(
    'plan_step_overdue',
    'plan_step_overdue',
    kind: NotificationKind.planStepOverdue,
    withActor: false,
    facts: _step,
    en: ('Step overdue', 'Your step «Paint» is overdue'),
    ru: ('Шаг просрочен', 'Ваш шаг «Paint» просрочен'),
  ),
  _Row(
    'plan_step_late',
    'plan_step_late',
    kind: NotificationKind.planStepLate,
    withActor: false,
    facts: {..._step, 'relativeMinutes': 15},
    en: ('Step running late', '«Paint» is 15 min late'),
    ru: ('Шаг опаздывает', '«Paint» опаздывает на 15 мин'),
  ),
  _Row(
    'plan_cant_make',
    'plan_cant_make',
    kind: NotificationKind.planCantMake,
    facts: _step,
    en: ("Can't make it", "Anna can't make «Paint»"),
    ru: ('Не успевает', 'Anna не успевает к шагу «Paint»'),
  ),
  _Row(
    'plan_step_unassigned',
    'plan_step_unassigned',
    kind: NotificationKind.planStepUnassigned,
    withActor: false,
    facts: _step,
    en: ('Step has no one', '«Paint» has no one'),
    ru: ('Шаг без исполнителя', 'У шага «Paint» нет исполнителя'),
  ),
  _Row(
    'plan_edited',
    'plan_edited',
    kind: NotificationKind.planEdited,
    en: ('Plan updated', 'Anna edited the plan'),
    ru: ('План изменён', 'Anna изменил(а) план'),
  ),
  _Row(
    'plan_step_done',
    'plan_step_done',
    kind: NotificationKind.planStepDone,
    facts: _step,
    en: ('Step done', 'Anna finished «Paint»'),
    ru: ('Шаг выполнен', 'Anna: шаг «Paint» выполнен'),
  ),
  // Spec §5.2: forward_helped keeps today's sentences and headline
  // (BeaconNotificationCopyBuilder.forwardHelped), with {E} as the title.
  for (final done in [false, true])
    _Row(
      'forward_helped${done ? ' and done' : ''}',
      'forward_helped',
      withActor: false,
      facts: {
        'helperId': 'user-b',
        'done': done,
        'path': [
          {'userId': 'user-b', 'displayName': 'Boris', 'anonymousCount': 0},
        ],
      },
      en: (
        'Your forward helped',
        done
            ? "«Fix the roof» was completed with Boris's help"
            : 'Boris offered help with «Fix the roof»',
      ),
      ru: (
        'Ваша пересылка помогла',
        done
            ? '«Fix the roof» завершён с помощью Boris'
            : 'Boris предложил(а) помощь с «Fix the roof»',
      ),
    ),
  _Row(
    'closure_opened',
    'closure_opened',
    withActor: false,
    facts: {'epoch': 1},
    en: ('Time to sum up', 'Closing is open: mark who helped'),
    ru: (
      'Пора подвести итоги',
      'Подведение итогов открыто: отметьте, кто помог',
    ),
  ),
  _Row(
    'closure_opened_bookmark_only',
    'closure_opened_bookmark_only',
    withActor: false,
    facts: {'epoch': 1},
    identity: _identity(readable: false),
    en: ('Time to sum up', 'Closing is open'),
    ru: ('Пора подвести итоги', 'Подведение итогов открыто'),
  ),
  _Row(
    'closure_draft_reminder',
    'closure_draft_reminder',
    withActor: false,
    facts: {'epoch': 1},
    en: (
      'Finish your review',
      "Your review isn't sent yet; closing ends within a day",
    ),
    ru: (
      'Завершите свою оценку',
      'Ваша оценка ещё не отправлена; итоги закроются в течение суток',
    ),
  ),
  _Row(
    'closure_finalized',
    'closure_finalized',
    withActor: false,
    facts: {'epoch': 1},
    en: ('Request closed', 'The results are in'),
    ru: ('Запрос закрыт', 'Итоги подведены'),
  ),
  _Row(
    'closure_cancelled by a person',
    'closure_cancelled',
    en: ('Closing cancelled', 'Anna cancelled the closing'),
    ru: ('Подведение итогов отменено', 'Anna отменил(а) подведение итогов'),
  ),
  _Row(
    'closure_cancelled without an actor',
    'closure_cancelled',
    withActor: false,
    identity: _identity(actorName: null),
    en: ('Closing cancelled', 'Closing was cancelled'),
    ru: ('Подведение итогов отменено', 'Подведение итогов отменено'),
  ),
  _Row(
    'request_stale after quiet days',
    'request_stale',
    withActor: false,
    facts: {'staleReason': 'quiet', 'quietDays': 5},
    en: (
      'Your request has gone quiet',
      'No activity for 5 days. Close it, extend it or post an update',
    ),
    ru: (
      'В вашем запросе стало тихо',
      '5 дней без движения. Закройте, продлите или напишите новости',
    ),
  ),
  _Row(
    'request_stale after a passed deadline',
    'request_stale',
    withActor: false,
    facts: {'staleReason': 'deadlinePassed', 'endAt': '2026-11-21T15:00:00Z'},
    tzOffsetMinutes: 180,
    en: (
      'Your request has gone quiet',
      'The deadline passed on 21 Nov, 18:00. Close it or extend it',
    ),
    ru: (
      'В вашем запросе стало тихо',
      'Срок прошёл 21 ноября, 18:00. Закройте или продлите запрос',
    ),
  ),
  _Row(
    'mutual_connection_formed',
    'mutual_connection_formed',
    identity: _identity(label: null),
    en: ('New connection', 'You and Anna are now connected'),
    ru: ('Новая связь', 'Вы и Anna теперь на связи'),
  ),
  for (final (origin, copy) in [
    ('new_account', InviteAcceptedCopy.newAccount),
    ('existing_account', InviteAcceptedCopy.existingAccount),
  ])
    _Row(
      'invite_accepted via $origin',
      'invite_accepted',
      kind: NotificationKind.inviteAccepted,
      facts: {'inviteOrigin': origin},
      identity: _identity(label: null),
      en: ('Invitation accepted', 'Anna accepted your invitation. ${copy.en}'),
      ru: (
        'Приглашение принято',
        'Anna принял(а) ваше приглашение. ${copy.ru}',
      ),
    ),
  // Declared but never written: no fixed headline in the spec (today's copy),
  // so `en`/`ru` stay null and their «actor · headline» shape is checked in
  // their own group; they still run through the leak/RU/no-ISO sweeps.
  for (final key in _declaredNeverWritten) _Row(key, key),
];
