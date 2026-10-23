import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_entry_row.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_cubit.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fake_lobby_port.dart';

Widget _app(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('en'),
  home: child,
);

Widget _lobby(FakeLobbyPort port, String myId) {
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
        child: BeaconLobbyBody(myUserId: myId),
      ),
    ),
  );
}

void main() {
  group('the way into Questions follows the server policy', () {
    tearDown(() => GetIt.I.reset());

    Future<void> pumpRow(WidgetTester tester, FakeLobbyPort port) async {
      await GetIt.I.reset();
      GetIt.I.registerSingleton<BeaconLobbyCase>(
        lobbyCaseFor(port, FakeRealtimeSyncPort()),
      );
      await tester.pumpWidget(
        _app(const Scaffold(body: BeaconLobbyEntryRow(beaconId: 'B1'))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shown with the message count when the viewer may read', (
      tester,
    ) async {
      final port = FakeLobbyPort(viewerId: 'Unina')
        ..messagesList.add(
          const BeaconLobbyMessage(
            id: 'M1',
            authorId: 'Uauthor',
            authorName: 'Anna',
            body: 'The 18th',
          ),
        );
      await pumpRow(tester, port);
      expect(find.text('Questions'), findsOneWidget);
      expect(find.text('1 message'), findsOneWidget);
      expect(port.calls, contains('access'));
      // Probing never opens (creates) the Questions scope.
      expect(port.calls, isNot(contains('open')));
    });

    testWidgets('hidden when the server says no', (tester) async {
      await pumpRow(tester, FakeLobbyPort(viewerId: 'Ustranger'));
      expect(find.text('Questions'), findsNothing);
    });
  });

  group('Questions screen', () {
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

    testWidgets('author: remove someone (confirm dialog), then let them back '
        'in; names come from the server', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Uauthor')
        ..messagesList.addAll([ninaMsg, annaMsg]);
      await tester.pumpWidget(_lobby(port, 'Uauthor'));
      await tester.pumpAndSettle();
      expect(find.text('Which Saturday?'), findsOneWidget);
      // One remove button: on Nina's message, not on the author's own.
      final remove = find.byTooltip('Remove from Questions');
      expect(remove, findsOneWidget);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.byType(TenturaConfirmDialog), findsOneWidget);
      expect(find.text('Remove Nina from Questions?'), findsOneWidget);
      await tester.tap(find.text('Remove from Questions').last);
      await tester.pumpAndSettle();
      expect(port.banned, ['Unina']);
      expect(find.text('Removed from Questions'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Removed from Questions: 1 person'),
        findsOneWidget,
      );
      expect(find.byTooltip('Remove from Questions'), findsNothing);
      await tester.tap(find.text('Removed from Questions'));
      await tester.pumpAndSettle();
      expect(find.text('Name of Unina'), findsOneWidget);
      await tester.tap(find.text('Let back in'));
      await tester.pumpAndSettle();
      expect(port.banned, isEmpty);
    });

    testWidgets('empty: the design-system empty state explains Questions', (
      tester,
    ) async {
      final port = FakeLobbyPort(viewerId: 'Unina');
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      expect(find.byType(TenturaEmptyState), findsOneWidget);
      expect(find.text('No questions yet'), findsOneWidget);
      expect(find.byKey(const Key('beaconLobbyComposer')), findsOneWidget);
    });

    testWidgets('a recipient: no remove buttons; can post', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Unina')..messagesList.add(annaMsg);
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove from Questions'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('beaconLobbyComposer')),
        'How many boxes?',
      );
      await tester.tap(find.byKey(const Key('beaconLobbySend')));
      await tester.pumpAndSettle();
      expect(find.text('How many boxes?'), findsOneWidget);
      expect(port.calls, contains('post How many boxes?'));
    });

    testWidgets('read-only standing: reads, no composer, says why', (
      tester,
    ) async {
      final port = FakeLobbyPort(viewerId: 'Unina')
        ..messagesList.add(annaMsg)
        ..canPost = false;
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      expect(find.text('The 18th'), findsOneWidget);
      expect(find.byKey(const Key('beaconLobbyComposer')), findsNothing);
      expect(find.byKey(const Key('beaconLobbyReadOnly')), findsOneWidget);
    });

    testWidgets('outside the audience: Questions say who they are for', (
      tester,
    ) async {
      final port = FakeLobbyPort(viewerId: 'Unina')..banned.add('Unina');
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      expect(
        find.text('Questions are for the people this request was sent to.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('beaconLobbyComposer')), findsNothing);
    });

    testWidgets('offline: a retry, not the access message', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Unina')..failNext = true;
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beaconLobbyUnavailable')), findsNothing);
      expect(find.byKey(const Key('beaconLobbyComposer')), findsNothing);
    });

    testWidgets('long history: "Show earlier messages" pages back', (
      tester,
    ) async {
      final port = FakeLobbyPort(viewerId: 'Unina');
      for (var i = 0; i < 60; i++) {
        port.messagesList.add(
          BeaconLobbyMessage(
            id: 'M$i',
            authorId: 'Uauthor',
            authorName: 'Anna',
            body: 'm$i',
            createdAt: DateTime.utc(2026).add(Duration(minutes: i)),
          ),
        );
      }
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beaconLobbyLoadOlder')), findsOneWidget);
      await tester.tap(find.byKey(const Key('beaconLobbyLoadOlder')));
      await tester.pumpAndSettle();
      expect(port.calls, contains('messages before'));
      expect(find.byKey(const Key('beaconLobbyLoadOlder')), findsNothing);
    });
  });

  group('#655 the entry row re-reads its access', () {
    tearDown(() => GetIt.I.reset());

    testWidgets('when the Request page reports a new standing (joined)', (
      tester,
    ) async {
      await GetIt.I.reset();
      // Not in the audience yet: the row is hidden.
      final port = FakeLobbyPort(viewerId: 'Uilya', offerers: {});
      GetIt.I.registerSingleton<BeaconLobbyCase>(
        lobbyCaseFor(port, FakeRealtimeSyncPort()),
      );
      final standing = ValueNotifier<Object>(('B1', false));
      addTearDown(standing.dispose);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ValueListenableBuilder<Object>(
              valueListenable: standing,
              builder: (_, value, _) =>
                  BeaconLobbyEntryRow(beaconId: 'B1', standing: value),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(BeaconLobbyEntryRow.entryKey), findsNothing);
      final reads = port.calls.where((c) => c == 'access').length;

      // Offered help and was let in; no realtime hint reached this viewer.
      port.offerers.add('Uilya');
      standing.value = ('B1', true);
      await tester.pumpAndSettle();
      expect(port.calls.where((c) => c == 'access').length, reads + 1);
      expect(find.byKey(BeaconLobbyEntryRow.entryKey), findsOneWidget);
    });

    testWidgets('after a failed read, retries instead of hiding the row for '
        'good', (tester) async {
      await GetIt.I.reset();
      final port = FakeLobbyPort(viewerId: 'Uauthor')..failNext = true;
      GetIt.I.registerSingleton<BeaconLobbyCase>(
        lobbyCaseFor(port, FakeRealtimeSyncPort()),
      );
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: BeaconLobbyEntryRow(beaconId: 'B1', isAuthor: true),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(BeaconLobbyEntryRow.entryKey), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(BeaconLobbyEntryRow.entryKey), findsOneWidget);
      // The author is addressed as the one who answers.
      expect(
        find.textContaining('People you sent this request to'),
        findsOneWidget,
      );
    });
  });

  group('#657 copy follows who is reading', () {
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

    testWidgets("the author: answer copy, and the author's messages are "
        'marked', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Uauthor')
        ..messagesList.addAll([ninaMsg, annaMsg]);
      await tester.pumpWidget(_lobby(port, 'Uauthor'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ask the author'), findsNothing);
      expect(
        find.textContaining('People you sent this request to'),
        findsOneWidget,
      );
      expect(find.text('Write an answer'), findsOneWidget);
      expect(find.byKey(const Key('beaconLobbyAuthorBadge')), findsOneWidget);
    });

    testWidgets('a recipient: ask copy; the author badge marks the answer', (
      tester,
    ) async {
      final port = FakeLobbyPort(viewerId: 'Unina')
        ..messagesList.addAll([ninaMsg, annaMsg]);
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ask the author'), findsOneWidget);
      expect(find.text('Ask a question'), findsOneWidget);
      expect(find.byKey(const Key('beaconLobbyAuthorBadge')), findsOneWidget);
    });

    for (final (reason, text) in [
      (BeaconLobbyLimitReason.cantHelp, "You said you can't help"),
      (BeaconLobbyLimitReason.withdrew, 'You withdrew your help offer'),
      (BeaconLobbyLimitReason.declined, 'The author declined your help offer'),
      (BeaconLobbyLimitReason.closed, 'This request is closed'),
    ]) {
      testWidgets('read-only names the reason: ${reason.name}', (
        tester,
      ) async {
        final port = FakeLobbyPort(viewerId: 'Unina')
          ..messagesList.add(annaMsg)
          ..canPost = false
          ..limitReason = reason;
        await tester.pumpWidget(_lobby(port, 'Unina'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('beaconLobbyComposer')), findsNothing);
        expect(find.textContaining(text), findsOneWidget);
        expect(find.textContaining('the request is closed, or'), findsNothing);
      });
    }

    testWidgets('the author of a closed Request: told it is closed, never '
        '"offer help", and no one to remove', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Uauthor')
        ..messagesList.addAll([ninaMsg, annaMsg])
        ..canPost = false
        ..limitReason = BeaconLobbyLimitReason.closed;
      await tester.pumpWidget(_lobby(port, 'Uauthor'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This request is closed'), findsOneWidget);
      expect(find.textContaining('Offer help'), findsNothing);
      expect(find.byTooltip('Remove from Questions'), findsNothing);
    });

    testWidgets('the remove confirmation holds whether or not they offered '
        'help', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Uauthor')
        ..messagesList.add(ninaMsg);
      await tester.pumpWidget(_lobby(port, 'Uauthor'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from Questions'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Their help offer stays'), findsNothing);
      expect(
        find.textContaining("This doesn't touch a help offer they made"),
        findsOneWidget,
      );
    });

    testWidgets('removed by the author: says so', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Unina')
        ..banned.add('Unina')
        ..limitReason = BeaconLobbyLimitReason.removed;
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      expect(
        find.text('The author removed you from Questions on this request.'),
        findsOneWidget,
      );
    });
  });

  group('#658 desktop composer', () {
    testWidgets('Enter (the send action) sends, like the Chat composer', (
      tester,
    ) async {
      final port = FakeLobbyPort(viewerId: 'Unina');
      await tester.pumpWidget(_lobby(port, 'Unina'));
      await tester.pumpAndSettle();
      final composer = find.byKey(const Key('beaconLobbyComposer'));
      expect(
        tester.widget<TextField>(composer).textInputAction,
        TextInputAction.send,
      );
      await tester.enterText(composer, 'Which Saturday?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(port.calls, contains('post Which Saturday?'));
      expect(find.text('Which Saturday?'), findsOneWidget);
      // Cleared for the next question.
      expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
    });
  });
}
