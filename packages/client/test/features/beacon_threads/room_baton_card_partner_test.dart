// Partner card on a «Who'll take it?» baton (baton together plan C3): a named
// partner sees one prompt per invite with Join / Can't, then «Can't after
// all» once joined, then the outcome. Never other people, tiers or counts.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _batonId = 'baton-1';

BeaconParticipant _participant(String userId, String title) =>
    BeaconParticipant(
      id: 'p-$userId',
      beaconId: 'b-baton',
      userId: userId,
      role: 0,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      userTitle: title,
    );

final _participants = [
  _participant('a', 'Anna'),
  _participant('b', 'Boris'),
  _participant('c', 'Clara'),
  _participant('me', 'Viewer'),
];

RoomBatonPartnerInvite _invite(String id, String title, String status) =>
    RoomBatonPartnerInvite(fromUserId: id, title: title, status: status);

RoomBatonPartnerData _partner({
  required List<RoomBatonPartnerInvite> invites,
  RoomBatonStatus status = RoomBatonStatus.collecting,
  RoomBatonOutcome? outcome,
}) => RoomBatonPartnerData(
  id: _batonId,
  status: status,
  outcome: outcome,
  partnerInvites: invites,
);

Widget _card(
  RoomBatonPartnerData baton, {
  Locale locale = const Locale('en'),
}) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: locale,
  home: MediaQuery(
    data: const MediaQueryData(size: Size(400, 900)),
    child: TenturaResponsiveScope(
      child: Scaffold(
        body: SingleChildScrollView(
          child: RoomBatonCard(
            baton: baton,
            participants: _participants,
            viewerUserId: 'me',
            batonAuthorUserId: 'author',
          ),
        ),
      ),
    ),
  ),
);

List<String> _stringsUnder(WidgetTester tester, Finder scope) {
  final out = <String>[];
  for (final w in tester.widgetList(
    find.descendant(of: scope, matching: find.byWidgetPredicate((_) => true)),
  )) {
    switch (w) {
      case Text(:final data, :final textSpan, :final semanticsLabel):
        out.addAll([?data, ?textSpan?.toPlainText(), ?semanticsLabel]);
      case RichText(:final text):
        out.add(text.toPlainText());
      case Tooltip(:final message):
        out.addAll([?message]);
      case Semantics(:final properties):
        out.addAll([?properties.label, ?properties.value, ?properties.hint]);
      case Icon(:final semanticLabel):
        out.addAll([?semanticLabel]);
    }
  }
  return out;
}

/// No Material button or icon button at all (not only no bare label).
void _expectNoOtherTappables(WidgetTester tester, {int allowed = 0}) {
  final found = find.descendant(
    of: find.byType(RoomBatonCard),
    matching: find.byWidgetPredicate(
      (w) => w is ButtonStyleButton || w is IconButton,
    ),
  );
  expect(found.evaluate().length, allowed);
}

void _expectNoActions(List<String> labels) {
  for (final l in labels) {
    expect(find.text(l), findsNothing, reason: l);
  }
}

const _allActions = ['Join', "Can't", "Can't after all"];

void main() {
  group('Partner card with a pending invite', () {
    testWidgets("shows the prompt, Join, Can't and the note", (tester) async {
      await tester.pumpWidget(
        _card(_partner(invites: [_invite('a', 'Anna', 'pending')])),
      );
      expect(
        find.text('Anna wants to take this on together with you.'),
        findsOneWidget,
      );
      expect(find.text('Join'), findsOneWidget);
      expect(find.text("Can't"), findsOneWidget);
      expect(
        find.text(
          'This is not taking it yet: the author chooses who takes it.',
        ),
        findsOneWidget,
      );
      expect(find.text('Looking for someone to take it.'), findsNothing);
    });

    testWidgets('two invites each get their own prompt and buttons', (
      tester,
    ) async {
      await tester.pumpWidget(
        _card(
          _partner(
            invites: [
              _invite('a', 'Anna', 'pending'),
              _invite('b', 'Boris', 'pending'),
            ],
          ),
        ),
      );
      expect(
        find.text('Anna wants to take this on together with you.'),
        findsOneWidget,
      );
      expect(
        find.text('Boris wants to take this on together with you.'),
        findsOneWidget,
      );
      expect(find.text('Join'), findsNWidgets(2));
      expect(find.text("Can't"), findsNWidgets(2));
    });
  });

  group('Partner card after joining', () {
    testWidgets("shows the joined copy and only Can't after all", (
      tester,
    ) async {
      await tester.pumpWidget(
        _card(_partner(invites: [_invite('a', 'Anna', 'accepted')])),
      );
      expect(
        find.text(
          "You'll take it together with Anna. "
          "You can change your mind while it's open.",
        ),
        findsOneWidget,
      );
      expect(find.text("Can't after all"), findsOneWidget);
      expect(find.text('Join'), findsNothing);
      expect(find.text("Can't"), findsNothing);
      _expectNoOtherTappables(tester, allowed: 1);
    });
  });

  group('Partner card outcomes', () {
    testWidgets('you: both took it, no actions', (tester) async {
      await tester.pumpWidget(
        _card(
          _partner(
            status: RoomBatonStatus.taken,
            outcome: RoomBatonOutcome.you,
            invites: [_invite('a', 'Anna', 'accepted')],
          ),
        ),
      );
      expect(find.text('You and Anna took it.'), findsOneWidget);
      _expectNoActions(_allActions);
      _expectNoOtherTappables(tester);
    });

    testWidgets('someone else: thanks, no actions', (tester) async {
      await tester.pumpWidget(
        _card(
          _partner(
            status: RoomBatonStatus.taken,
            outcome: RoomBatonOutcome.someoneElse,
            invites: [_invite('a', 'Anna', 'accepted')],
          ),
        ),
      );
      expect(
        find.text('Someone else was selected. Thanks for offering.'),
        findsOneWidget,
      );
      _expectNoActions(_allActions);
      _expectNoOtherTappables(tester);
    });

    testWidgets('closed: no longer needed, no actions', (tester) async {
      await tester.pumpWidget(
        _card(
          _partner(
            status: RoomBatonStatus.cancelled,
            outcome: RoomBatonOutcome.closed,
            invites: [_invite('a', 'Anna', 'pending')],
          ),
        ),
      );
      expect(find.text('No longer needed.'), findsOneWidget);
      _expectNoActions(_allActions);
      _expectNoOtherTappables(tester);
    });
  });

  group('Partner card privacy', () {
    const leaks = ['priority', 'tier', 'rank', 'приоритет', 'ранг'];
    for (final locale in const [Locale('en'), Locale('ru')]) {
      testWidgets(
        'names nobody else and shows no tier, count or author action '
        '(${locale.languageCode})',
        (tester) async {
          await tester.pumpWidget(
            _card(
              _partner(invites: [_invite('a', 'Anna', 'pending')]),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          final card = find.byType(RoomBatonCard);
          final strings = _stringsUnder(tester, card);
          // The prompt must exist, otherwise absence below proves nothing.
          expect(strings.any((t) => t.contains('Anna')), isTrue);
          for (final text in strings) {
            final lower = text.toLowerCase();
            expect(
              text,
              isNot(
                matches(
                  RegExp(
                    r'\d+\s*(answer|repl|respon|ответ|откликн|помо)|'
                    r'(answers?|replies|ответов)\D{0,3}\d',
                    caseSensitive: false,
                  ),
                ),
              ),
              reason: 'no answer count in "$text"',
            );
            for (final l in leaks) {
              expect(lower, isNot(contains(l)), reason: '"$text" ~ "$l"');
            }
            for (final n in ['Boris', 'Clara', 'Viewer']) {
              expect(text, isNot(contains(n)), reason: text);
            }
            for (final w in [
              'can help',
              "can't help",
              'together with…',
              'choose now',
              'могу помочь',
              'не смогу помочь',
              'вместе с кем-то',
              'выбрать',
            ]) {
              expect(lower, isNot(contains(w)), reason: '"$text" ~ "$w"');
            }
          }
          expect(
            find.descendant(
              of: card,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Badge ||
                    w is Slider ||
                    w is ProgressIndicator ||
                    (w is Icon &&
                        const [
                          Icons.looks_one,
                          Icons.looks_two,
                          Icons.looks_3,
                          Icons.filter_1,
                          Icons.numbers,
                        ].contains(w.icon)),
              ),
            ),
            findsNothing,
          );
        },
      );
    }
  });

  group('Partner card in Russian', () {
    testWidgets('pending invite copy', (tester) async {
      await tester.pumpWidget(
        _card(
          _partner(invites: [_invite('a', 'Анна', 'pending')]),
          locale: const Locale('ru'),
        ),
      );
      expect(
        find.text('Анна предлагает взяться за это вместе с вами.'),
        findsOneWidget,
      );
      expect(find.text('Возьмусь вместе'), findsOneWidget);
      expect(find.text('Не смогу'), findsOneWidget);
      expect(
        find.text('Это ещё не значит, что вы взялись: выбирает автор.'),
        findsOneWidget,
      );
    });

    testWidgets('accepted invite offers a change of mind', (tester) async {
      await tester.pumpWidget(
        _card(
          _partner(invites: [_invite('a', 'Анна', 'accepted')]),
          locale: const Locale('ru'),
        ),
      );
      expect(find.text('Всё-таки не смогу'), findsOneWidget);
    });
  });
}
