import 'package:test/test.dart';

import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';

// RU/EN receipt copy for taking a baton «together»: invitation, the
// partner's answer (accepted / declined). Exact strings, readable and
// unreadable entity.

NotificationIdentity _identity({bool readable = true}) => NotificationIdentity(
  entityKind: NotificationEntityKind.request,
  label: 'Fix the roof',
  tombstone: false,
  readable: readable,
  actorName: 'Anna',
  actorHidden: false,
  relatedLabel: null,
  expired: false,
);

NotificationCopy _render(
  String key,
  Map<String, Object?> facts, {
  required String locale,
  bool readable = true,
}) => const NotificationCopyRenderer().render(
  presentationKey: key,
  kind: null,
  facts: {'beaconId': 'beacon-1', 'actorUserId': 'actor-1', ...facts},
  identity: _identity(readable: readable),
  locale: locale,
  tzOffsetMinutes: 0,
  now: DateTime.utc(2026, 11, 16, 9),
);

class _Case {
  const _Case(
    this.name,
    this.key,
    this.facts,
    this.enHead,
    this.enReadable,
    this.enUnreadable,
    this.ruHead,
    this.ruReadable,
    this.ruUnreadable,
  );
  final String name;
  final String key;
  final Map<String, Object?> facts;
  final String enHead;
  final String enReadable;
  final String enUnreadable;
  final String ruHead;
  final String ruReadable;
  final String ruUnreadable;
}

const _cases = [
  _Case(
    'partner asked',
    'baton_partner_asked',
    {'excerpt': 'hello'},
    'Take it on together?',
    'Anna wants to take it on together with you: hello',
    'Anna wants to take it on together with you',
    'Взяться вместе?',
    'Anna предлагает взяться вместе: hello',
    'Anna предлагает взяться вместе',
  ),
  _Case(
    'partner accepted',
    'baton_partner_answered',
    {'accepted': true, 'excerpt': 'hello'},
    'Together',
    'Anna will take it on with you: hello',
    'Anna will take it on with you',
    'Вместе',
    'Anna возьмётся вместе с вами: hello',
    'Anna возьмётся вместе с вами',
  ),
  _Case(
    'partner declined',
    'baton_partner_answered',
    {'accepted': false, 'excerpt': 'hello'},
    "Can't join",
    "Anna can't join you. Answer again: hello",
    "Anna can't join you. Answer again",
    'Не сможет присоединиться',
    'Anna не сможет присоединиться. Ответьте ещё раз: hello',
    'Anna не сможет присоединиться. Ответьте ещё раз',
  ),
];

void main() {
  for (final c in _cases) {
    group('${c.name} copy', () {
      test('English, readable Request', () {
        final copy = _render(c.key, c.facts, locale: 'en');
        expect(copy.headline, c.enHead);
        expect(copy.sentence, c.enReadable);
      });
      test('English, unreadable Request drops the excerpt', () {
        final copy = _render(c.key, c.facts, locale: 'en', readable: false);
        expect(copy.headline, c.enHead);
        expect(copy.sentence, c.enUnreadable);
      });
      test('Russian, readable Request', () {
        final copy = _render(c.key, c.facts, locale: 'ru');
        expect(copy.headline, c.ruHead);
        expect(copy.sentence, c.ruReadable);
      });
      test('Russian, unreadable Request drops the excerpt', () {
        final copy = _render(c.key, c.facts, locale: 'ru', readable: false);
        expect(copy.headline, c.ruHead);
        expect(copy.sentence, c.ruUnreadable);
      });
      test('Russian copy never glues «с» to a person name', () {
        for (final readable in [true, false]) {
          final copy = _render(
            c.key,
            c.facts,
            locale: 'ru',
            readable: readable,
          );
          expect(copy.headline, isNot(matches(RegExp('с [A-ZА-ЯЁ]'))));
          expect(copy.sentence, isNot(matches(RegExp('с [A-ZА-ЯЁ]'))));
        }
      });
    });
  }

  for (final c in _cases) {
    test('${c.name}: a hidden actor is «Someone» / «Кто-то», never named', () {
      for (final (locale, lead) in [('en', 'Someone'), ('ru', 'Кто-то')]) {
        final copy = const NotificationCopyRenderer().render(
          presentationKey: c.key,
          kind: null,
          facts: {'beaconId': 'b', 'actorUserId': 'a', ...c.facts},
          identity: const NotificationIdentity(
            entityKind: NotificationEntityKind.request,
            label: 'Fix the roof',
            tombstone: false,
            readable: true,
            actorName: 'SECRET-ACTOR',
            actorHidden: true,
            relatedLabel: null,
            expired: false,
          ),
          locale: locale,
          tzOffsetMinutes: 0,
          now: DateTime.utc(2026, 11, 16, 9),
        );
        expect(copy.sentence, startsWith(lead), reason: locale);
        expect(copy.sentence, isNot(contains('SECRET-ACTOR')));
      }
    });
  }
}
