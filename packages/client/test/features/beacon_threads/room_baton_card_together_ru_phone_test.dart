// Baton together cards in Russian on the narrow phone (375x667): candidate
// (pending / accepted / declined / invited), partner (pending / joined / taken)
// and author (confirmed pair + pending pair) keep canonical copy, do not
// overflow, and keep every action button on screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/phone_surface.dart';

const _long = 'Святослав Игоревич Чернышевский-Подольский';
const _long2 = 'Анастасия Владимировна Новосёлова-Белозёрская';

BeaconParticipant _p(String id, String t) => BeaconParticipant(
  id: 'p-$id',
  beaconId: 'b1',
  userId: id,
  role: 0,
  status: 0,
  roomAccess: RoomAccessBits.admitted,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  userTitle: t,
);

Widget _app(Widget card) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('ru'),
  home: MediaQuery(
    data: const MediaQueryData(size: kPhoneSurface),
    child: TenturaResponsiveScope(
      child: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  ),
);

Widget _candidate(RoomBatonCandidateData b) => RoomBatonCard(
  baton: b,
  participants: [_p('me', 'Я'), _p('x', _long), _p('author', 'Автор')],
  viewerUserId: 'me',
  batonAuthorUserId: 'author',
  onRespond: (_, {partnerUserId}) {},
  onPartnerRespond: (_, {required accept}) {},
);

Future<void> _pump(WidgetTester tester, Widget w) async {
  await usePhoneSurface(tester);
  await tester.pumpWidget(_app(w));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// The button holding [label] is whole on screen (its box, not just the text).
void _onScreen(WidgetTester tester, String label) {
  final button = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  expect(button, findsOneWidget, reason: label);
  final r = tester.getRect(button);
  expect(r.left, greaterThanOrEqualTo(0), reason: label);
  expect(r.top, greaterThanOrEqualTo(0), reason: label);
  expect(r.right, lessThanOrEqualTo(kPhoneSurface.width), reason: label);
  expect(r.bottom, lessThanOrEqualTo(kPhoneSurface.height), reason: label);
}

final _ru = L10nRu();

void _answerButtonsOnScreen(WidgetTester tester) {
  for (final l in [
    _ru.batonCandidateCanHelp,
    _ru.batonCandidateCantHelp,
    _ru.batonTogetherAction,
  ]) {
    _onScreen(tester, l);
  }
}

RoomBatonCandidateData _mine(String status, {
  RoomBatonResponse r = RoomBatonResponse.canHelp,
  List<RoomBatonPartnerInvite> invites = const [],
}) => RoomBatonCandidateData(
  id: 'baton-1',
  status: RoomBatonStatus.collecting,
  myResponse: r,
  myPartner: RoomBatonMyPartner(id: 'x', title: _long, status: status),
  partnerInvites: invites,
);

void main() {
  group('Candidate card, RU 375x667', () {
    testWidgets('pending partner shows the waiting line', (tester) async {
      await _pump(tester, _candidate(_mine('pending')));
      expect(
        find.text('Ваш ответ: могу помочь вместе. Ждём ответа: $_long.'),
        findsOneWidget,
      );
      _answerButtonsOnScreen(tester);
    });

    testWidgets('accepted partner shows the together line', (tester) async {
      await _pump(tester, _candidate(_mine('accepted')));
      expect(
        find.text('Ваш ответ: могу помочь. Вместе с вами: $_long.'),
        findsOneWidget,
      );
    });

    testWidgets('declined partner returns to the three answers', (
      tester,
    ) async {
      await _pump(
        tester,
        _candidate(_mine('declined', r: RoomBatonResponse.waiting)),
      );
      expect(
        find.text('$_long не сможет присоединиться. Сможете помочь?'),
        findsOneWidget,
      );
      _answerButtonsOnScreen(tester);
    });

    testWidgets('own answer and an invitation show together', (tester) async {
      await _pump(
        tester,
        _candidate(
          _mine(
            'pending',
            invites: const [
              RoomBatonPartnerInvite(
                fromUserId: 'y',
                title: _long2,
                status: 'pending',
              ),
            ],
          ),
        ),
      );
      expect(
        find.text('Ваш ответ: могу помочь вместе. Ждём ответа: $_long.'),
        findsOneWidget,
      );
      expect(
        find.text('$_long2 предлагает взяться за это вместе с вами.'),
        findsOneWidget,
      );
      _onScreen(tester, 'Возьмусь вместе');
      _onScreen(tester, 'Не смогу');
    });
  });

  group('Partner card, RU 375x667', () {
    RoomBatonPartnerData partner(
      String s, {
      RoomBatonOutcome? outcome,
      RoomBatonStatus st = RoomBatonStatus.collecting,
    }) => RoomBatonPartnerData(
      id: 'baton-1',
      status: st,
      outcome: outcome,
      partnerInvites: [
        RoomBatonPartnerInvite(fromUserId: 'a', title: _long, status: s),
      ],
    );
    Widget card(RoomBatonPartnerData b) => RoomBatonCard(
      baton: b,
      participants: [_p('me', 'Я')],
      viewerUserId: 'me',
      batonAuthorUserId: 'author',
    );

    testWidgets('pending invite: prompt, note, both buttons on screen', (
      tester,
    ) async {
      await _pump(tester, card(partner('pending')));
      expect(
        find.text('$_long предлагает взяться за это вместе с вами.'),
        findsOneWidget,
      );
      expect(
        find.text('Это ещё не значит, что вы взялись: выбирает автор.'),
        findsOneWidget,
      );
      _onScreen(tester, 'Возьмусь вместе');
      _onScreen(tester, 'Не смогу');
    });

    testWidgets('accepted invite offers a change of mind', (tester) async {
      await _pump(tester, card(partner('accepted')));
      expect(
        find.text(
          'Вы согласились взяться вместе. Вместе с вами: $_long. '
          'Пока выбор не сделан, это можно изменить.',
        ),
        findsOneWidget,
      );
      _onScreen(tester, 'Всё-таки не смогу');
    });

    testWidgets('outcome you names the partner', (tester) async {
      await _pump(
        tester,
        card(
          partner(
            'accepted',
            outcome: RoomBatonOutcome.you,
            st: RoomBatonStatus.taken,
          ),
        ),
      );
      expect(find.text('Вы взялись. Вместе с вами: $_long.'), findsOneWidget);
    });
  });

  group('Author card, RU 375x667', () {
    testWidgets('a confirmed pair is one ellipsized row; pending pair waits', (
      tester,
    ) async {
      await _pump(
        tester,
        RoomBatonCard(
          baton: const RoomBatonAuthorData(
            id: 'baton-1',
            status: RoomBatonStatus.collecting,
            candidates: [
              RoomBatonCandidate(
                userId: 'u1',
                title: _long,
                tier: 1,
                response: RoomBatonResponse.canHelp,
                partner: RoomBatonTaker(id: 'u2', title: _long2),
              ),
              RoomBatonCandidate(
                userId: 'u3',
                title: 'Клара',
                tier: 1,
                response: RoomBatonResponse.waiting,
              ),
            ],
            allAnswered: false,
            eligibleCount: 1,
            pairs: [
              RoomBatonConfirmedPair(takerId: 'u1', partnerId: 'u2', tier: 1),
            ],
          ),
          onSelect: (_) {},
          onCancel: () {},
        ),
      );
      final pair = find.text('$_long и $_long2');
      expect(pair, findsOneWidget);
      final t = tester.widget<Text>(pair);
      expect(t.maxLines, 1);
      expect(t.overflow, TextOverflow.ellipsis);
      // Rendered on one line: as tall as a plain single-line name.
      expect(
        tester.getSize(pair).height,
        tester.getSize(find.text('Клара')).height,
      );
      expect(tester.getRect(pair).right, lessThanOrEqualTo(375));
      expect(find.text('могут вместе'), findsOneWidget);
      expect(find.text('Клара'), findsOneWidget);
      expect(find.text(_ru.batonStatusWaiting), findsOneWidget);
    });
  });
}
