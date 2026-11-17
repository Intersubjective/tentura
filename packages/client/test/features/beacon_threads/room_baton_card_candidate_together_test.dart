// «Together with…» on an asked person's baton card (baton together plan C2):
//  - a third action opens the plan person picker and calls respond with a
//    partner id;
//  - partner pending / accepted / declined copy and invitations from others;
//  - no leak of other candidates' names; replace-pair confirm when needed;
//  - gated on [kBatonTogetherEnabled] while the baton is still collecting.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewer = Profile(id: 'u-viewer', displayName: 'Viewer Self');
const _batonAuthor = Profile(id: 'u-anna', displayName: 'Anna Author');
const _partnerBoris = Profile(id: 'u-boris', displayName: 'Boris Mate');
const _admittedClara = Profile(id: 'u-clara', displayName: 'Clara Helper');

const _batonId = 'baton-1';

/// Canonical EN copy from `docs/plans/baton-together-plan.md` §4.
const _togetherAction = 'Together with…';
const _pickTitle = 'Who will you take it with?';

const _waiting = RoomBatonCandidateData(
  id: _batonId,
  status: RoomBatonStatus.collecting,
  myResponse: RoomBatonResponse.waiting,
);

RoomBatonCandidateData _withPartner({
  required String status,
  String partnerId = 'u-boris',
  String partnerTitle = 'Boris Mate',
  RoomBatonResponse myResponse = RoomBatonResponse.canHelp,
  List<RoomBatonPartnerInvite> partnerInvites = const [],
}) =>
    RoomBatonCandidateData(
      id: _batonId,
      status: RoomBatonStatus.collecting,
      myResponse: myResponse,
      myPartner: RoomBatonMyPartner(
        id: partnerId,
        title: partnerTitle,
        status: status,
      ),
      partnerInvites: partnerInvites,
    );

Widget _localized(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 900)),
        child: TenturaResponsiveScope(
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );

BeaconParticipant _participant(String userId, String title) => BeaconParticipant(
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

final _roomParticipants = [
  _participant(_batonAuthor.id, _batonAuthor.displayName),
  _participant(_viewer.id, _viewer.displayName),
  _participant(_partnerBoris.id, _partnerBoris.displayName),
  _participant(_admittedClara.id, _admittedClara.displayName),
];

Widget _cardHarness(
  RoomBatonCandidateData baton, {
  void Function(bool canHelp, {String? partnerUserId})? onRespond,
  bool? togetherEnabled,
}) =>
    _localized(
      // Omitting togetherEnabled exercises the released default.
      togetherEnabled == null
          ? RoomBatonCard(
              baton: baton,
              participants: _roomParticipants,
              viewerUserId: _viewer.id,
              batonAuthorUserId: _batonAuthor.id,
              onRespond: onRespond,
            )
          : RoomBatonCard(
              baton: baton,
              participants: _roomParticipants,
              viewerUserId: _viewer.id,
              batonAuthorUserId: _batonAuthor.id,
              togetherEnabled: togetherEnabled,
              onRespond: onRespond,
            ),
    );

Future<void> _focusTogetherAction(WidgetTester tester) async {
  final target = find.text(_togetherAction);
  final element = target.evaluate().single;
  for (var i = 0; i < 30; i++) {
  if (Focus.of(element).hasFocus) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('keyboard focus never reached the together action');
}

List<String> _stringsUnder(Finder scope, WidgetTester tester) {
  final out = <String>[];
  for (final w in tester.widgetList(
    find.descendant(of: scope, matching: find.byWidgetPredicate((_) => true)),
  )) {
    switch (w) {
      case Text(:final data, :final textSpan, :final semanticsLabel):
        out.addAll([?data, ?textSpan?.toPlainText(), ?semanticsLabel]);
      case RichText(:final text):
        out.add(text.toPlainText());
      case Semantics(:final properties):
        out.addAll([?properties.label, ?properties.value, ?properties.hint]);
    }
  }
  return out;
}

const _replacePairConfirmPrefix = 'This replaces taking it with';

void main() {
  group('Together action on a collecting baton candidate card', () {
    test('candidate body gates the together action on kBatonTogetherEnabled', () {
      final src = File(
        'lib/features/beacon_threads/ui/widget/room_baton_card.dart',
      ).readAsStringSync();
      expect(src, contains('kBatonTogetherEnabled'));
      expect(
        src,
        contains('l10n.batonTogetherAction'),
        reason: 'together copy must come from l10n, not a hard-coded string',
      );
      expect(
        src,
        isNot(contains("'$_togetherAction'")),
        reason: 'EN copy belongs in ARB via batonTogetherAction',
      );
    });

    testWidgets('shows the together action when kBatonTogetherEnabled is true',
        (tester) async {
      expect(kBatonTogetherEnabled, isTrue);
      await tester.pumpWidget(
        _cardHarness(_waiting, togetherEnabled: kBatonTogetherEnabled),
      );
      await tester.pumpAndSettle();

      expect(find.text(_togetherAction), findsOneWidget);
    });

    testWidgets('hides the together action once the baton is no longer collecting',
        (tester) async {
      await tester.pumpWidget(
        _cardHarness(
          const RoomBatonCandidateData(
            id: _batonId,
            status: RoomBatonStatus.taken,
            myResponse: RoomBatonResponse.waiting,
            outcome: RoomBatonOutcome.someoneElse,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_togetherAction), findsNothing);
    });

    testWidgets('shows the together action on a collecting candidate card', (
      tester,
    ) async {
      await tester.pumpWidget(_cardHarness(_waiting));
      await tester.pumpAndSettle();

      expect(find.text(_togetherAction), findsOneWidget);
    });
  });

  group('Plan person picker for a together partner', () {
    test('candidate body reuses showPlanPersonPicker for the partner sheet', () {
      final src = File(
        'lib/features/beacon_threads/ui/widget/room_baton_card.dart',
      ).readAsStringSync();
      expect(src, contains('showPlanPersonPicker'));
      expect(src, contains('l10n.batonTogetherPickTitle'));
    });

    testWidgets('lists admitted people except the viewer and the baton author',
        (tester) async {
      await tester.pumpWidget(_cardHarness(_waiting));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_togetherAction));
      await tester.pumpAndSettle();

      expect(find.text(_pickTitle), findsOneWidget);
      expect(find.text(_partnerBoris.displayName), findsOneWidget);
      expect(find.text(_admittedClara.displayName), findsOneWidget);
      expect(find.text(_viewer.displayName), findsNothing);
      expect(find.text(_batonAuthor.displayName), findsNothing);
    });

    testWidgets('opens the picker from the keyboard on the focused together action',
        (tester) async {
      await tester.pumpWidget(_cardHarness(_waiting));
      await tester.pumpAndSettle();

      await _focusTogetherAction(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text(_pickTitle), findsOneWidget);
    });
  });

  group('Answering together on the candidate card', () {
    testWidgets('respond includes the chosen partner user id after a pick', (
      tester,
    ) async {
      final responds =
          <({bool canHelp, String? partnerUserId})>[];
      await tester.pumpWidget(
        _cardHarness(
          _waiting,
          onRespond: (canHelp, {partnerUserId}) => responds.add(
            (canHelp: canHelp, partnerUserId: partnerUserId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_togetherAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_partnerBoris.displayName));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(responds, hasLength(1));
      expect(responds.single.canHelp, isTrue);
      expect(responds.single.partnerUserId, _partnerBoris.id);
    });
  });

  group('Together partner copy on the candidate card', () {
    testWidgets('shows pending copy while waiting for the named partner to answer',
        (tester) async {
      await tester.pumpWidget(
        _cardHarness(_withPartner(status: 'pending')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Your answer: can help together with ${_partnerBoris.displayName}. '
          'Waiting for ${_partnerBoris.displayName}.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows accepted copy once the named partner has joined', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardHarness(_withPartner(status: 'accepted')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Your answer: can help. Together with you: ${_partnerBoris.displayName}.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('returns to the prompt when the partner declined', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardHarness(
          _withPartner(
            status: 'declined',
            myResponse: RoomBatonResponse.waiting,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          "${_partnerBoris.displayName} can't join. Can you help?",
        ),
        findsOneWidget,
      );
      expect(find.text('Can help'), findsOneWidget);
      expect(find.text("Can't help"), findsOneWidget);
      expect(find.text(_togetherAction), findsOneWidget);
    });

    testWidgets('shows invitations from others who named the viewer', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardHarness(
          const RoomBatonCandidateData(
            id: _batonId,
            status: RoomBatonStatus.collecting,
            myResponse: RoomBatonResponse.waiting,
            partnerInvites: [
              RoomBatonPartnerInvite(
                fromUserId: 'u-dmitri',
                title: 'Dmitri Inviter',
                status: 'pending',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Dmitri Inviter wants to take this on together with you.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Together answer privacy on the candidate card', () {
    testWidgets('names only the viewer’s chosen partner, not other candidates',
        (tester) async {
      await tester.pumpWidget(
        _cardHarness(_withPartner(status: 'pending')),
      );
      await tester.pumpAndSettle();

      final strings = _stringsUnder(find.byType(RoomBatonCard), tester);
      expect(strings, isNotEmpty);
      for (final text in strings) {
        expect(text, isNot(contains(_admittedClara.displayName)));
        expect(text, isNot(contains('Clara Helper')));
        expect(text, isNot(contains(_batonAuthor.displayName)));
      }
      expect(
        strings.any((s) => s.contains(_partnerBoris.displayName)),
        isTrue,
        reason: 'the pending copy names the partner the viewer chose',
      );
    });
  });

  group('Replace an already accepted together pair', () {
    const previousPartner = Profile(
      id: 'u-yuri',
      displayName: 'Yuri Previous',
    );

    testWidgets(
        'does not ask to replace a pair while the current partner is still pending',
        (tester) async {
      await tester.pumpWidget(
        _cardHarness(_withPartner(status: 'pending')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_togetherAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_partnerBoris.displayName));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '$_replacePairConfirmPrefix ${previousPartner.displayName}.',
        ),
        findsNothing,
      );
    });

    testWidgets(
        'does not ask to replace a pair when the viewer has not named anyone yet',
        (tester) async {
      await tester.pumpWidget(_cardHarness(_waiting));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_togetherAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_partnerBoris.displayName));
      await tester.pumpAndSettle();

      expect(find.textContaining(_replacePairConfirmPrefix), findsNothing);
    });

    testWidgets('asks for confirmation before naming someone else', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardHarness(
          _withPartner(
            status: 'accepted',
            partnerId: previousPartner.id,
            partnerTitle: previousPartner.displayName,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_togetherAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_partnerBoris.displayName));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This replaces taking it with ${previousPartner.displayName}.',
        ),
        findsOneWidget,
      );
    });
  });
}
