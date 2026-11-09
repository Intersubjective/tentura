import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_cubit.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_chat.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_entry_row.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart'
    show RoomBodyHarnessPresenceCubit, RoomBodyHarnessProfileCubit;
import 'fake_lobby_port.dart';

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: locale,
  home: child,
);

Future<void> _pumpFrames(WidgetTester tester, [int frames = 20]) async {
  // Bounded: the chat surface hosts animations that never settle.
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The Questions content as [myId] sees it, over [port] and a room holding
/// [messages] (all on the Questions thread).
Future<void> _pumpLobby(
  WidgetTester tester,
  FakeLobbyPort port,
  String myId, {
  List<RoomMessage> messages = const [],
  Size size = const Size(700, 900),
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final effects = RecordingEffects();
  final profileCubit = RoomBodyHarnessProfileCubit(
    Profile(id: myId, displayName: myId),
  );
  final presenceCubit = RoomBodyHarnessPresenceCubit();
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<PresenceCubit>(presenceCubit)
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<BeaconThreadsCase>(
      roomCubitMakeCase(
        FakeBeaconThreadsRepository(userId: myId)..messages = messages,
      ),
    )
    ..registerSingleton<BeaconFactCardRepository>(
      FakeBeaconFactCardRepository(),
    )
    ..registerSingleton<CoordinationItemRoomSync>(CoordinationItemRoomSync())
    ..registerSingleton<PresenceRepository>(roomCubitFakePresenceRepository())
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: profileCubit),
        BlocProvider<PresenceCubit>.value(value: presenceCubit),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(effects)),
      ],
      child: _app(
        TenturaResponsiveScope(
          child: Scaffold(
            body: BlocProvider(
              create: (_) {
                final cubit = BeaconLobbyCubit(
                  lobbyCaseFor(port, FakeRealtimeSyncPort()),
                  effects,
                  beaconId: 'B1',
                );
                unawaited(cubit.load());
                return cubit;
              },
              child: const BeaconLobbyChat(),
            ),
          ),
        ),
        locale: locale,
      ),
    ),
  );
  await _pumpFrames(tester);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

/// The Questions composer's hint.
String? _composerHint(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(TestIds.key(TestIds.roomMessageInput)))
    .decoration
    ?.hintText;

RoomMessage _message(String id, String authorId, String name, String body) =>
    RoomMessage(
      id: id,
      beaconId: 'B1',
      authorId: authorId,
      author: Profile(id: authorId, displayName: name),
      body: body,
      createdAt: DateTime.utc(2026, 10, 1, 12),
      threadItemId: 'Llobby',
    );

/// Opens the actions of the chat message reading [body].
Future<void> _openActions(
  WidgetTester tester,
  String body, {
  bool secondaryTap = false,
}) async {
  final text = find.ancestor(
    of: find.textContaining(body),
    matching: find.byWidgetPredicate(
      (w) => w is RoomMessageTextBody || w is ShowMoreText,
    ),
  );
  final position = tester.getTopLeft(text.first) + const Offset(8, 8);
  if (secondaryTap) {
    final mouse = await tester.startGesture(
      position,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
  } else {
    await tester.longPressAt(position);
  }
  await _pumpFrames(tester, 10);
}

void main() {
  group('Questions message removal actions', () {
    for (final secondaryTap in [false, true]) {
      final gesture = secondaryTap ? 'secondary tap' : 'long press';
      testWidgets(
        '$gesture lets the author confirm removal of another person once',
        (tester) async {
          final port = FakeLobbyPort(viewerId: 'Uauthor');
          await _pumpLobby(
            tester,
            port,
            'Uauthor',
            messages: [
              _message('M1', 'Unina', 'Nina', 'Which Saturday?'),
              _message('M2', 'Uauthor', 'Anna', 'The 18th'),
            ],
          );

          Future<void> openActions(String body) =>
              _openActions(tester, body, secondaryTap: secondaryTap);

          await openActions('The 18th');
          expect(find.text('Copy text'), findsOneWidget);
          expect(find.text('Remove from Questions'), findsNothing);
          await tester.tapAt(const Offset(10, 10));
          await _pumpFrames(tester, 10);

          await openActions('Which Saturday?');
          expect(find.text('Remove from Questions'), findsOneWidget);
          expect(port.banned, isEmpty);
          expect(port.calls.where((c) => c.startsWith('ban ')), isEmpty);
          await tester.tap(find.text('Remove from Questions'));
          await _pumpFrames(tester, 10);
          expect(find.byType(TenturaConfirmDialog), findsOneWidget);
          expect(find.text('Remove Nina from Questions?'), findsOneWidget);
          expect(port.calls.where((c) => c.startsWith('ban ')), isEmpty);
          expect(port.banned, isEmpty);
          await tester.tap(find.text('Remove from Questions').last);
          await _pumpFrames(tester, 10);
          expect(port.calls.where((c) => c.startsWith('ban ')), ['ban Unina']);
          expect(port.banned, ['Unina']);
        },
      );
      testWidgets('$gesture hides removal on a closed Request', (tester) async {
        final port = FakeLobbyPort(viewerId: 'Uauthor')
          ..takesOffers = false
          ..canPost = false
          ..limitReason = BeaconLobbyLimitReason.closed;
        await _pumpLobby(
          tester,
          port,
          'Uauthor',
          messages: [
            _message('M1', 'Unina', 'Nina', 'Which Saturday?'),
          ],
        );
        expect(find.textContaining('Which Saturday?'), findsWidgets);
        await _openActions(
          tester,
          'Which Saturday?',
          secondaryTap: secondaryTap,
        );
        expect(find.text('Copy text'), findsOneWidget);
        expect(find.text('Remove from Questions'), findsNothing);
        expect(port.calls.where((c) => c.startsWith('ban ')), isEmpty);
        expect(port.banned, isEmpty);
      });

      testWidgets('$gesture hides removal for a recipient', (tester) async {
        final port = FakeLobbyPort(viewerId: 'Unina');
        await _pumpLobby(
          tester,
          port,
          'Unina',
          messages: [
            _message('M2', 'Uauthor', 'Anna', 'The 18th'),
          ],
        );
        expect(find.textContaining('The 18th'), findsWidgets);
        await _openActions(tester, 'The 18th', secondaryTap: secondaryTap);
        expect(find.text('Copy text'), findsOneWidget);
        expect(find.text('Remove from Questions'), findsNothing);
        expect(port.calls.where((c) => c.startsWith('ban ')), isEmpty);
        expect(port.banned, isEmpty);
      });
    }
  });

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
      final port = FakeLobbyPort(viewerId: 'Unina')..messageCount = 1;
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
    final nina = _message('M1', 'Unina', 'Nina', 'Which Saturday?');
    final anna = _message('M2', 'Uauthor', 'Anna', 'The 18th');

    testWidgets('author: remove someone from their message (confirm dialog), '
        'then let them back in; names come from the server', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Uauthor');
      await _pumpLobby(tester, port, 'Uauthor', messages: [nina, anna]);
      // Not offered on the author's own message.
      await _openActions(tester, 'The 18th');
      expect(find.text('Remove from Questions'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await _pumpFrames(tester, 10);
      await _openActions(tester, 'Which Saturday?');
      await tester.tap(find.text('Remove from Questions'));
      await _pumpFrames(tester, 10);
      expect(find.byType(TenturaConfirmDialog), findsOneWidget);
      expect(find.text('Remove Nina from Questions?'), findsOneWidget);
      expect(find.textContaining('Their help offer stays'), findsNothing);
      expect(
        find.textContaining("This doesn't touch a help offer they made"),
        findsOneWidget,
      );
      expect(port.banned, isEmpty);
      expect(port.calls.where((c) => c.startsWith('ban ')), isEmpty);
      await tester.tap(find.text('Remove from Questions').last);
      await _pumpFrames(tester, 10);
      expect(port.banned, ['Unina']);
      expect(port.calls.where((c) => c.startsWith('ban ')), ['ban Unina']);
      expect(find.text('Removed from Questions'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Removed from Questions: 1 person'),
        findsOneWidget,
      );
      await tester.tap(find.text('Removed from Questions'));
      await _pumpFrames(tester, 10);
      expect(find.text('Name of Unina'), findsOneWidget);
      await tester.tap(find.text('Let back in'));
      await _pumpFrames(tester, 10);
      expect(port.banned, isEmpty);
    });

    testWidgets('the author of a closed Request: no one to remove', (
      tester,
    ) async {
      final port = FakeLobbyPort(viewerId: 'Uauthor')
        ..canPost = false
        ..limitReason = BeaconLobbyLimitReason.closed;
      await _pumpLobby(tester, port, 'Uauthor', messages: [nina]);
      await _openActions(tester, 'Which Saturday?');
      expect(find.text('Remove from Questions'), findsNothing);
    });

    testWidgets('a recipient: no remove action', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Unina');
      await _pumpLobby(tester, port, 'Unina', messages: [anna]);
      await _openActions(tester, 'The 18th');
      expect(find.text('Remove from Questions'), findsNothing);
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
          ..canPost = false
          ..limitReason = reason;
        await _pumpLobby(tester, port, 'Unina', messages: [anna]);
        expect(find.textContaining('The 18th'), findsWidgets);
        expect(_composerHint(tester), contains(text));
        expect(
          _composerHint(tester),
          isNot(contains('the request is closed, or')),
        );
      });
    }

    testWidgets('outside the audience: Questions say who they are for', (
      tester,
    ) async {
      final port = FakeLobbyPort(viewerId: 'Unina')..banned.add('Unina');
      await _pumpLobby(tester, port, 'Unina');
      expect(
        find.text(lookupL10n(const Locale('en')).beaconLobbyUnavailable),
        findsOneWidget,
      );
      expect(find.byKey(TestIds.key(TestIds.roomMessageInput)), findsNothing);
    });

    testWidgets('offline: a retry, not the access message', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Unina')..failNext = true;
      await _pumpLobby(tester, port, 'Unina');
      expect(find.byKey(const Key('beaconLobbyUnavailable')), findsNothing);
      expect(find.byKey(TestIds.key(TestIds.roomMessageInput)), findsNothing);
    });

    testWidgets('removed by the author: says so', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Unina')
        ..banned.add('Unina')
        ..limitReason = BeaconLobbyLimitReason.removed;
      await _pumpLobby(tester, port, 'Unina');
      expect(
        find.text('The author removed you from Questions on this request.'),
        findsOneWidget,
      );
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
        find.textContaining(
          lookupL10n(const Locale('en')).beaconLobbyEntrySubtitleAuthor,
        ),
        findsOneWidget,
      );
    });
  });

  group('#657 the Questions line follows role and Request state', () {
    tearDown(() => GetIt.I.reset());

    // Each line in full, as the English copy has it.
    final en = lookupL10n(const Locale('en'));
    final author = en.beaconLobbyEntrySubtitleAuthor;
    final recipient = en.beaconLobbyEntrySubtitle;
    final helper = en.beaconLobbyEntrySubtitleHelper;
    final closed = en.beaconLobbyEntrySubtitleClosed;
    final authorClosed = en.beaconLobbyEntrySubtitleAuthorClosed;

    // (case, viewer, helper, takes offers, can post, reason, expected)
    final cases =
        <(String, String, bool, bool, bool, BeaconLobbyLimitReason?, String)>[
          ('author, open', 'Uauthor', false, true, true, null, author),
          (
            'author, Final check',
            'Uauthor',
            false,
            false,
            true,
            null,
            authorClosed,
          ),
          (
            'author, closed',
            'Uauthor',
            false,
            false,
            false,
            BeaconLobbyLimitReason.closed,
            authorClosed,
          ),
          (
            'recipient before offering',
            'Unina',
            false,
            true,
            true,
            null,
            recipient,
          ),
          ('pending offer', 'Unina', true, true, true, null, helper),
          ('admitted helper', 'Unina', true, true, true, null, helper),
          (
            'admitted helper, closed',
            'Unina',
            true,
            false,
            false,
            BeaconLobbyLimitReason.closed,
            closed,
          ),
          (
            'recipient, closed',
            'Unina',
            false,
            false,
            false,
            BeaconLobbyLimitReason.closed,
            closed,
          ),
          (
            "Can't help reader, closed",
            'Unina',
            false,
            false,
            false,
            BeaconLobbyLimitReason.cantHelp,
            closed,
          ),
        ];

    FakeLobbyPort portFor(
      String viewer, {
      required bool isHelper,
      required bool takesOffers,
      required bool canPost,
      required BeaconLobbyLimitReason? reason,
    }) => FakeLobbyPort(viewerId: viewer)
      ..isHelper = isHelper
      ..takesOffers = takesOffers
      ..canPost = canPost
      ..limitReason = reason;

    for (final (name, viewer, isHelper, takesOffers, canPost, reason, line)
        in cases) {
      testWidgets('screen header: $name', (tester) async {
        final port = portFor(
          viewer,
          isHelper: isHelper,
          takesOffers: takesOffers,
          canPost: canPost,
          reason: reason,
        );
        await _pumpLobby(tester, port, viewer);
        expect(find.textContaining(line), findsOneWidget);
        for (final other in {
          author,
          recipient,
          helper,
          closed,
          authorClosed,
        }..remove(line)) {
          expect(find.textContaining(other), findsNothing, reason: other);
        }
      });

      testWidgets('Overview row: $name', (tester) async {
        await GetIt.I.reset();
        final port = portFor(
          viewer,
          isHelper: isHelper,
          takesOffers: takesOffers,
          canPost: canPost,
          reason: reason,
        );
        GetIt.I.registerSingleton<BeaconLobbyCase>(
          lobbyCaseFor(port, FakeRealtimeSyncPort()),
        );
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: BeaconLobbyEntryRow(
                beaconId: 'B1',
                isAuthor: viewer == 'Uauthor',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining(line), findsOneWidget);
        for (final other in {
          author,
          recipient,
          helper,
          closed,
          authorClosed,
        }..remove(line)) {
          expect(find.textContaining(other), findsNothing, reason: other);
        }
      });
    }

    testWidgets('the Request card of a recipient on a closed Request says '
        'it is closed', (tester) async {
      await GetIt.I.reset();
      final port = portFor(
        'Unina',
        isHelper: false,
        takesOffers: false,
        canPost: false,
        reason: BeaconLobbyLimitReason.cantHelp,
      );
      GetIt.I.registerSingleton<BeaconLobbyCase>(
        lobbyCaseFor(port, FakeRealtimeSyncPort()),
      );
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: BeaconLobbyEntryRow(beaconId: 'B1', prominent: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(closed), findsOneWidget);
      expect(find.textContaining(recipient), findsNothing);
    });

    testWidgets("closed beats Can't help in the read-only note: nobody can "
        'offer again', (tester) async {
      final port = portFor(
        'Unina',
        isHelper: false,
        takesOffers: false,
        canPost: false,
        reason: BeaconLobbyLimitReason.cantHelp,
      );
      await _pumpLobby(tester, port, 'Unina');
      expect(_composerHint(tester), contains('This request is closed'));
      expect(_composerHint(tester), isNot(contains('Offer help')));
    });

    testWidgets("open Request: Can't help still names the reader's own act", (
      tester,
    ) async {
      final port = portFor(
        'Unina',
        isHelper: false,
        takesOffers: true,
        canPost: false,
        reason: BeaconLobbyLimitReason.cantHelp,
      );
      await _pumpLobby(tester, port, 'Unina');
      expect(_composerHint(tester), contains("You said you can't help"));
    });
  });

  group('Questions copy names its audience: people the Request was sent to '
      'or who found it', () {
    tearDown(() => GetIt.I.reset());

    const phone = Size(375, 667);
    const ru = Locale('ru');
    final ruL10n = lookupL10n(ru);
    final enL10n = lookupL10n(const Locale('en'));

    /// The audience as the copy states it, in one clause: those the Request
    /// was sent to OR those who found it. Never "everyone who can see it":
    /// parent/child Request members see a Request but have no Questions.
    void expectAudienceWording(String text, {required bool russian}) {
      if (russian) {
        expect(
          text,
          matches(
            RegExp(
              r'отправ[^.]*\sили\s[^.]*наш(ёл|ел|ли|едш)'
              r'|наш(ёл|ел|ли|едш)[^.]*\sили\s[^.]*отправ',
            ),
          ),
          reason: text,
        );
        for (final wrong in [
          'кто видит',
          'кто его видит',
          'родител',
          'подзапрос',
          'связанн',
        ]) {
          expect(text, isNot(contains(wrong)), reason: text);
        }
      } else {
        expect(
          text,
          matches(
            RegExp(
              r'\bsent\b[^.]*\bor\b[^.]*\bfound\b'
              r'|\bfound\b[^.]*\bor\b[^.]*\bsent\b',
            ),
          ),
          reason: text,
        );
        for (final wrong in [
          'who can see',
          'parent',
          'sub-request',
          'related request',
        ]) {
          expect(text.toLowerCase(), isNot(contains(wrong)), reason: text);
        }
      }
    }

    /// [shown] is laid out in full on the phone: no overflow reported by
    /// any flex or box (Flutter reports it as an error, which the test
    /// binding hands to takeException), the paragraph is not cut off, and it
    /// lies inside the 375x667 screen.
    void expectFitsOnPhone(WidgetTester tester, String shown) {
      final error = tester.takeException();
      expect(error, isNull, reason: 'layout error at 375x667: $error');
      final text = find.textContaining(shown);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: text, matching: find.byType(RichText)).first,
      );
      expect(paragraph.didExceedMaxLines, isFalse, reason: shown);
      final rect = tester.getRect(text);
      expect(
        rect.left >= 0 &&
            rect.top >= 0 &&
            rect.right <= phone.width &&
            rect.bottom <= phone.height,
        isTrue,
        reason: 'subtitle at $rect is outside the 375x667 screen',
      );
    }

    // (case, viewer, helper, takes offers, can post, reason, line)
    final cases =
        <
          (
            String,
            String,
            bool,
            bool,
            bool,
            BeaconLobbyLimitReason?,
            String Function(L10n),
          )
        >[
          (
            'recipient before offering',
            'Unina',
            false,
            true,
            true,
            null,
            (l) => l.beaconLobbyEntrySubtitle,
          ),
          (
            'author, open',
            'Uauthor',
            false,
            true,
            true,
            null,
            (l) => l.beaconLobbyEntrySubtitleAuthor,
          ),
          (
            'pending offer',
            'Unina',
            true,
            true,
            true,
            null,
            (l) => l.beaconLobbyEntrySubtitleHelper,
          ),
          (
            'recipient, closed',
            'Unina',
            false,
            false,
            false,
            BeaconLobbyLimitReason.closed,
            (l) => l.beaconLobbyEntrySubtitleClosed,
          ),
          (
            'author, closed',
            'Uauthor',
            false,
            false,
            false,
            BeaconLobbyLimitReason.closed,
            (l) => l.beaconLobbyEntrySubtitleAuthorClosed,
          ),
        ];

    for (final (name, viewer, isHelper, takesOffers, canPost, reason, line)
        in cases) {
      testWidgets('Request page row in Russian on a phone: $name', (
        tester,
      ) async {
        tester.view.physicalSize = phone;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await GetIt.I.reset();
        final port = FakeLobbyPort(viewerId: viewer)
          ..isHelper = isHelper
          ..takesOffers = takesOffers
          ..canPost = canPost
          ..limitReason = reason;
        GetIt.I.registerSingleton<BeaconLobbyCase>(
          lobbyCaseFor(port, FakeRealtimeSyncPort()),
        );
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: BeaconLobbyEntryRow(
                beaconId: 'B1',
                isAuthor: viewer == 'Uauthor',
              ),
            ),
            locale: ru,
          ),
        );
        await tester.pumpAndSettle();
        final shown = line(ruL10n);
        expect(find.textContaining(shown), findsOneWidget);
        expectFitsOnPhone(tester, shown);
        expectAudienceWording(shown, russian: true);
        expectAudienceWording(line(enL10n), russian: false);
      });

      testWidgets('Questions screen header in Russian on a phone: $name', (
        tester,
      ) async {
        final port = FakeLobbyPort(viewerId: viewer)
          ..isHelper = isHelper
          ..takesOffers = takesOffers
          ..canPost = canPost
          ..limitReason = reason;
        await _pumpLobby(tester, port, viewer, size: phone, locale: ru);
        final shown = line(ruL10n);
        expect(find.textContaining(shown), findsOneWidget);
        expectFitsOnPhone(tester, shown);
        expectAudienceWording(shown, russian: true);
      });
    }

    testWidgets('outside the audience in Russian on a phone: Questions say '
        'they are for people it was sent to or who found it', (tester) async {
      final port = FakeLobbyPort(viewerId: 'Ustranger', offerers: {});
      await _pumpLobby(tester, port, 'Ustranger', size: phone, locale: ru);
      final shown = ruL10n.beaconLobbyUnavailable;
      expect(
        find.descendant(
          of: find.byKey(const Key('beaconLobbyUnavailable')),
          matching: find.text(shown, findRichText: true),
        ),
        findsOneWidget,
      );
      expectFitsOnPhone(tester, shown);
      expectAudienceWording(shown, russian: true);
      expectAudienceWording(enL10n.beaconLobbyUnavailable, russian: false);
    });
  });
}
