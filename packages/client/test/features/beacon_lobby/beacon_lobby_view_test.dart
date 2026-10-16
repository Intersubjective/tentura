import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_entry_row.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_cubit.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_body.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fake_lobby_port.dart';

final _t = DateTime.utc(2026, 10, 14);
const _author = Profile(id: 'Uauthor', displayName: 'Anna');

Widget _app(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('en'),
  home: child,
);

BeaconViewState _state({
  required String myId,
  List<TimelineHelpOffer> offers = const [],
  BeaconKind kind = BeaconKind.request,
}) => BeaconViewState(
  beacon: Beacon(
    id: 'B1',
    title: 'Moving day',
    author: _author,
    createdAt: _t,
    updatedAt: _t,
    kind: kind,
  ),
  myProfile: Profile(id: myId, displayName: 'Me'),
  helpOffers: offers,
);

TimelineHelpOffer _offer(String id, {bool withdrawn = false}) =>
    TimelineHelpOffer(
      user: Profile(id: id, displayName: 'Nina'),
      message: 'I have a van',
      createdAt: _t,
      updatedAt: _t,
      isWithdrawn: withdrawn,
    );

Widget _lobby(FakeLobbyPort port, String myId, {Map<String, String>? names}) {
  final sync = FakeRealtimeSyncPort();
  return _app(
    Scaffold(
      body: BlocProvider(
        create: (_) {
          final cubit = BeaconLobbyCubit(
            lobbyCaseFor(port, sync),
            RecordingEffects(),
            beaconId: 'B1',
          );
          unawaited(cubit.load());
          return cubit;
        },
        child: BeaconLobbyBody(myUserId: myId, knownNames: names ?? const {}),
      ),
    ),
  );
}

void main() {
  group('who sees the way into the lobby (U088)', () {
    test('author and live offerers; not others, not withdrawn, not Posts', () {
      expect(canOpenBeaconLobby(_state(myId: 'Uauthor')), isTrue);
      expect(
        canOpenBeaconLobby(_state(myId: 'Unina', offers: [_offer('Unina')])),
        isTrue,
      );
      expect(canOpenBeaconLobby(_state(myId: 'Ustranger')), isFalse);
      expect(
        canOpenBeaconLobby(
          _state(myId: 'Unina', offers: [_offer('Unina', withdrawn: true)]),
        ),
        isFalse,
      );
      expect(
        canOpenBeaconLobby(_state(myId: 'Uauthor', kind: BeaconKind.post)),
        isFalse,
      );
    });

    testWidgets('the entry row shows "Lobby" only when allowed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: BeaconLobbyEntryRow(
              state: _state(myId: 'Unina', offers: [_offer('Unina')]),
            ),
          ),
        ),
      );
      expect(find.text('Lobby'), findsOneWidget);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: BeaconLobbyEntryRow(state: _state(myId: 'Ux')),
          ),
        ),
      );
      expect(find.text('Lobby'), findsNothing);
    });
  });

  group('lobby screen (U088)', () {
    const ninaMsg = BeaconLobbyMessage(
      id: 'M1',
      authorId: 'Unina',
      authorName: 'Nina',
      body: 'Which Saturday?',
    );
    const annaMsg = BeaconLobbyMessage(
      id: 'M2',
      authorId: 'Uauthor',
      authorName: 'Anna',
      body: 'The 18th',
    );

    testWidgets('author: remove someone, then let them back in', (
      tester,
    ) async {
      final port = FakeLobbyPort(viewerId: 'Uauthor')
        ..messagesList.addAll([ninaMsg, annaMsg]);
      await tester.pumpWidget(_lobby(port, 'Uauthor'));
      await tester.pumpAndSettle();
      expect(find.text('Which Saturday?'), findsOneWidget);
      // One remove button: on Nina's message, not on the author's own.
      final remove = find.byTooltip('Remove from lobby');
      expect(remove, findsOneWidget);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.text('Remove Nina from the lobby?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Remove from lobby'));
      await tester.pumpAndSettle();
      expect(port.banned, ['Unina']);
      // The count is a plain number after the label, not "(1)".
      expect(find.text('Removed from lobby'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.byTooltip('Remove from lobby'), findsNothing);
      await tester.tap(find.text('Removed from lobby'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Let back in'));
      await tester.pumpAndSettle();
      expect(port.banned, isEmpty);
    });

    testWidgets('a removed person with no known name shows "Someone", never '
        'an id', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Uauthor')..banned.add('Ughost42');
      await tester.pumpWidget(_lobby(port, 'Uauthor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Removed from lobby'));
      await tester.pumpAndSettle();
      expect(find.text('Someone'), findsOneWidget);
      expect(find.textContaining('Ughost42'), findsNothing);
    });

    testWidgets('offerer: no remove buttons; can post', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Unina')..messagesList.add(annaMsg);
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove from lobby'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('beaconLobbyComposer')),
        'How many boxes?',
      );
      await tester.tap(find.byKey(const Key('beaconLobbySend')));
      await tester.pumpAndSettle();
      expect(find.text('How many boxes?'), findsOneWidget);
      expect(port.calls, contains('post How many boxes?'));
    });

    testWidgets('closed Request: the lobby reads, no composer', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Unina')
        ..messagesList.add(annaMsg)
        ..canPost = false;
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      expect(find.text('The 18th'), findsOneWidget);
      expect(find.byKey(const Key('beaconLobbyComposer')), findsNothing);
    });

    testWidgets('removed or no offer: the lobby says who it is for', (
      tester,
    ) async {
      final port = FakeLobbyPort(viewerId: 'Unina')..banned.add('Unina');
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The lobby is only for the author and people with an active help '
          'offer.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('beaconLobbyComposer')), findsNothing);
    });

    testWidgets('offline: a retry, not the access message', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Unina')..failNext = true;
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The lobby is only for the author'),
        findsNothing,
      );
      expect(find.byKey(const Key('beaconLobbyComposer')), findsNothing);
    });
  });
}
