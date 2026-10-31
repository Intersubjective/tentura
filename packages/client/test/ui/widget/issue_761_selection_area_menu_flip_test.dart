// #761: on desktop web, HomeRoute crashed in release builds with null
// checks inside SelectionContainer (TENTURA-CLIENT-44, while building),
// in its dispose while the tree was finalized (TENTURA-CLIENT-42), and in
// heroes.dart (TENTURA-CLIENT-49, likely the same broken subtree).
//
// Cause: Flutter's SelectableRegion wraps its inner SelectionContainer in a
// browser-menu view only while BrowserContextMenu.enabled is on. The room's
// BrowserContextMenuHold (#623) flips that global flag when a room opens and
// when the last one closes. Text selectable OUTSIDE a room (profile, beacon
// view) that rebuilt after a flip re-created its inner container under a
// region that still had the old one registered: a second add (44, then 42
// when the old one was removed).
//
// Spec: once a flip has landed, every TenturaSelectionArea gets a fresh
// SelectableRegion (a selection outside a room is dropped then, accepted).
// The child is moved under the fresh region, not rebuilt: a ShowMoreText
// someone expanded stays expanded, and its text selects in the new region.
// No flip, no new region: ordinary rebuilds and stacked rooms keep the same
// region and its selection (#623).
//
// kIsWeb is false in VM tests, so the browser-menu wrapper itself never
// appears here; the test drives the web check and the two menu calls
// through BrowserContextMenuHold's seams and checks the region is replaced.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readmore/readmore.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/widget/browser_context_menu_hold.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura/ui/widget/tentura_selection_area.dart';

import '../../support/phone_surface.dart';

const _outside = 'Profile text';
const _room = 'Room text';
const _showMore = 'Show more';
const _showLess = 'Show less';
// Longer than ShowMoreText's three lines at the test window's width (about
// eleven lines in the test font), yet short enough that the expanded text
// still fits the 600 px window with a room under it.
final _description = List.filled(30, 'Profile description').join(' ');

void main() {
  final originalIsWeb = BrowserContextMenuHold.isWeb;
  final originalDisable = BrowserContextMenuHold.disableMenu;
  final originalEnable = BrowserContextMenuHold.enableMenu;

  late List<String> calls;
  late bool menuOffAtOnce;
  late bool menuOffFails;
  Completer<void>? menuOff;

  setUp(() {
    calls = [];
    menuOffAtOnce = false;
    menuOffFails = false;
    menuOff = null;
    BrowserContextMenuHold.isWeb = () => true;
    // Completers are made inside the call, on the test's fake clock.
    BrowserContextMenuHold.disableMenu = () {
      calls.add('disable');
      if (menuOffFails) return Future<void>.error(StateError('no menu'));
      if (menuOffAtOnce) return Future<void>.value();
      menuOff = Completer<void>();
      return menuOff!.future;
    };
    BrowserContextMenuHold.enableMenu = () async {
      calls.add('enable');
    };
  });

  tearDown(() {
    BrowserContextMenuHold.isWeb = originalIsWeb;
    BrowserContextMenuHold.disableMenu = originalDisable;
    BrowserContextMenuHold.enableMenu = originalEnable;
    BrowserContextMenuHold.debugReset();
  });

  late StateSetter setOuter;
  var rooms = <Key>[];
  var tick = 0;
  final navigatorKey = GlobalKey<NavigatorState>();

  Future<void> pumpHome(WidgetTester tester, {Widget? outside}) {
    rooms = [];
    tick = 0;
    return tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return Column(
                children: [
                  TenturaSelectionArea(
                    child: outside ?? Text('$_outside $tick'),
                  ),
                  for (final key in rooms)
                    BrowserContextMenuHold(
                      key: key,
                      child: const TenturaSelectionArea(child: Text(_room)),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> pumpHomeWithRoutes(WidgetTester tester, {Widget? outside}) {
    rooms = [];
    tick = 0;
    return tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        navigatorKey: navigatorKey,
        initialRoute: '/home',
        routes: {
          '/home': (context) => Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setOuter = setState;
                return Column(
                  children: [
                    TenturaSelectionArea(
                      child: outside ?? Text('$_outside $tick'),
                    ),
                    for (final key in rooms)
                      BrowserContextMenuHold(
                        key: key,
                        child: const TenturaSelectionArea(child: Text(_room)),
                      ),
                  ],
                );
              },
            ),
          ),
          '/profile': (_) => const Scaffold(body: Text('Profile page')),
        },
      ),
    );
  }

  Future<void> setRooms(WidgetTester tester, List<Key> keys) async {
    setOuter(() => rooms = keys);
    await tester.pump();
  }

  SelectableRegionState regionOf(WidgetTester tester, String text) =>
      tester.state<SelectableRegionState>(
        find.ancestor(
          of: find.textContaining(text).first,
          matching: find.byType(SelectableRegion),
        ),
      );

  Widget description() => ShowMoreText(
    _description,
    trimCollapsedText: _showMore,
    trimExpandedText: _showLess,
  );

  Finder descriptionText() => find.descendant(
    of: find.byType(ShowMoreText),
    matching: find.byType(RichText),
  );

  String shownDescription(WidgetTester tester) =>
      tester.widget<RichText>(descriptionText()).text.toPlainText();

  // Taps the ShowMoreText link through its own recognizer, the way a click on
  // it ends up, without depending on gesture arena details.
  void tapDescriptionLink(WidgetTester tester, String label) {
    TapGestureRecognizer? recognizer;
    tester.widget<RichText>(descriptionText()).text.visitChildren((span) {
      if (span is TextSpan &&
          span.text == label &&
          span.recognizer is TapGestureRecognizer) {
        recognizer = span.recognizer! as TapGestureRecognizer;
        return false;
      }
      return true;
    });
    expect(recognizer, isNotNull, reason: 'no "$label" link');
    recognizer!.onTap!();
  }

  void expectNoCrash(WidgetTester tester) {
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
  }

  testWidgets(
    '#761 opening and closing a room gives text outside it a fresh region',
    (tester) async {
      await pumpHome(tester);
      final before = regionOf(tester, _outside);

      await setRooms(tester, const [ValueKey('a')]);
      expect(calls, ['disable']);
      expect(
        identical(regionOf(tester, _outside), before),
        isTrue,
        reason: 'nothing has flipped while the menu call is in flight',
      );

      menuOff!.complete();
      await tester.pumpAndSettle();
      expectNoCrash(tester);
      expect(find.text(_room), findsOneWidget);
      final whileRoomOpen = regionOf(tester, _outside);
      expect(
        identical(whileRoomOpen, before),
        isFalse,
        reason: 'the menu went off: the old region must not be rebuilt',
      );

      await setRooms(tester, const []);
      await tester.pumpAndSettle();
      expectNoCrash(tester);
      expect(calls, ['disable', 'enable']);
      expect(
        identical(regionOf(tester, _outside), whileRoomOpen),
        isFalse,
        reason: 'the menu came back on: the old region must not be rebuilt',
      );
      expect(find.textContaining(_outside), findsOneWidget);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets('#761 a selection outside the room does not crash the flip', (
    tester,
  ) async {
    await pumpHome(tester);
    final before = regionOf(tester, _outside)
      ..selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    menuOffAtOnce = true;
    await setRooms(tester, const [ValueKey('a')]);
    await tester.pumpAndSettle();
    expectNoCrash(tester);

    final after = regionOf(tester, _outside);
    expect(identical(after, before), isFalse);
    // The fresh region still selects.
    after.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    expectNoCrash(tester);

    await setRooms(tester, const []);
    await tester.pumpAndSettle();
    expectNoCrash(tester);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets(
    '#761 an expanded description stays expanded across both flips',
    (tester) async {
      await pumpHome(tester, outside: description());
      expect(shownDescription(tester), contains(_showMore));
      tapDescriptionLink(tester, _showMore);
      await tester.pump();
      expect(shownDescription(tester), contains(_showLess));
      final state = tester.state<ReadMoreTextState>(find.byType(ShowMoreText));
      final regionBefore = regionOf(tester, 'Profile description');

      menuOffAtOnce = true;
      await setRooms(tester, const [ValueKey('a')]);
      await tester.pumpAndSettle();
      expectNoCrash(tester);
      final regionWhileRoomOpen = regionOf(tester, 'Profile description');
      expect(
        identical(regionWhileRoomOpen, regionBefore),
        isFalse,
        reason: 'the menu went off: the region is still replaced',
      );
      expect(
        identical(
          tester.state<ReadMoreTextState>(find.byType(ShowMoreText)),
          state,
        ),
        isTrue,
        reason: 'the description is moved under the new region, not rebuilt',
      );
      expect(
        shownDescription(tester),
        contains(_showLess),
        reason: 'opening a room must not collapse the description',
      );

      await setRooms(tester, const []);
      await tester.pumpAndSettle();
      expectNoCrash(tester);
      expect(calls, ['disable', 'enable']);
      expect(
        identical(regionOf(tester, 'Profile description'), regionWhileRoomOpen),
        isFalse,
        reason: 'the menu came back on: the region is still replaced',
      );
      expect(
        identical(
          tester.state<ReadMoreTextState>(find.byType(ShowMoreText)),
          state,
        ),
        isTrue,
      );
      expect(
        shownDescription(tester),
        contains(_showLess),
        reason: 'closing the last room must not collapse the description',
      );

      // Still the same live widget: it collapses on request.
      tapDescriptionLink(tester, _showLess);
      await tester.pump();
      expect(shownDescription(tester), contains(_showMore));
      expectNoCrash(tester);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    '#761 moved text selects in the fresh region, with no stale highlight',
    (tester) async {
      await pumpHome(tester, outside: description());
      final paragraph = tester.renderObject<RenderParagraph>(
        descriptionText(),
      );
      regionOf(
        tester,
        'Profile description',
      ).selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      expect(paragraph.selections, isNotEmpty);

      menuOffAtOnce = true;
      await setRooms(tester, const [ValueKey('a')]);
      await tester.pumpAndSettle();
      expectNoCrash(tester);
      expect(
        identical(
          tester.renderObject<RenderParagraph>(descriptionText()),
          paragraph,
        ),
        isTrue,
        reason: 'the text is moved under the new region, not rebuilt',
      );
      expect(
        paragraph.selections,
        isEmpty,
        reason: 'the old selection is dropped with the old region',
      );

      regionOf(
        tester,
        'Profile description',
      ).selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      expectNoCrash(tester);
      expect(
        paragraph.selections,
        isNotEmpty,
        reason: 'the moved text is registered with the fresh region',
      );

      await setRooms(tester, const []);
      await tester.pumpAndSettle();
      expectNoCrash(tester);
      expect(paragraph.selections, isEmpty);
      regionOf(
        tester,
        'Profile description',
      ).selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      expectNoCrash(tester);
      expect(paragraph.selections, isNotEmpty);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    '#761 guard: no flip, same region (rebuilds and stacked rooms, #623)',
    (tester) async {
      menuOffAtOnce = true;
      await pumpHome(tester);
      await setRooms(tester, const [ValueKey('a')]);
      await tester.pumpAndSettle();
      final outside = regionOf(tester, _outside);
      final room = regionOf(tester, _room);

      // An ordinary rebuild of the page.
      setOuter(() => tick++);
      await tester.pumpAndSettle();
      expect(identical(regionOf(tester, _outside), outside), isTrue);
      expect(identical(regionOf(tester, _room), room), isTrue);

      // A second room while the menu is already off: no flip.
      await setRooms(tester, const [ValueKey('a'), ValueKey('b')]);
      await tester.pumpAndSettle();
      expect(calls, ['disable']);
      expect(identical(regionOf(tester, _outside), outside), isTrue);
      expect(
        identical(regionOf(tester, _room), room),
        isTrue,
        reason: 'the first room keeps its region and its selection',
      );
      expectNoCrash(tester);

      await setRooms(tester, const []);
      await tester.pumpAndSettle();
      expectNoCrash(tester);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    '#761 guard: a menu call that fails flips nothing, so nothing is rebuilt',
    (tester) async {
      menuOffFails = true;
      await pumpHome(tester);
      final before = regionOf(tester, _outside);

      await setRooms(tester, const [ValueKey('a')]);
      await tester.pumpAndSettle();
      expectNoCrash(tester);
      expect(find.text(_room), findsOneWidget);
      expect(identical(regionOf(tester, _outside), before), isTrue);

      await setRooms(tester, const []);
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets('#761 guard: off the web nothing flips and the region stays', (
    tester,
  ) async {
    BrowserContextMenuHold.isWeb = () => false;
    await pumpHome(tester);
    final before = regionOf(tester, _outside);

    await setRooms(tester, const [ValueKey('a')]);
    await tester.pumpAndSettle();
    await setRooms(tester, const []);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(identical(regionOf(tester, _outside), before), isTrue);
    expect(BrowserContextMenuHold.menuFlips.value, 0);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets(
    '#761 re-key waits until the area is active on the current route',
    (tester) async {
      menuOffAtOnce = true;
      Completer<void>? enablePending;
      BrowserContextMenuHold.enableMenu = () {
        calls.add('enable');
        enablePending = Completer<void>();
        return enablePending!.future;
      };

      await pumpHomeWithRoutes(tester);
      final regionBefore = regionOf(tester, _outside);

      await setRooms(tester, const [ValueKey('a')]);
      await tester.pumpAndSettle();
      final regionRoomOpen = regionOf(tester, _outside);
      expect(identical(regionRoomOpen, regionBefore), isFalse);

      await setRooms(tester, const []);
      expect(enablePending, isNotNull);

      navigatorKey.currentState!.pushNamed('/profile');
      await tester.pump();

      enablePending!.complete();
      await tester.pump();
      expectNoCrash(tester);
      expect(
        identical(regionOf(tester, _outside), regionRoomOpen),
        isTrue,
        reason: 'flip while Home is covered must not re-key yet',
      );

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expectNoCrash(tester);
      expect(
        identical(regionOf(tester, _outside), regionRoomOpen),
        isFalse,
        reason: 're-key applies once Home is current again',
      );
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    '#761 flip pending during sign-out-like teardown does not re-key',
    (tester) async {
      menuOffAtOnce = true;
      Completer<void>? enablePending;
      BrowserContextMenuHold.enableMenu = () {
        calls.add('enable');
        enablePending = Completer<void>();
        return enablePending!.future;
      };

      await pumpHome(tester);
      await setRooms(tester, const [ValueKey('a')]);
      await tester.pumpAndSettle();
      await setRooms(tester, const []);
      expect(enablePending, isNotNull);

      enablePending!.complete();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expectNoCrash(tester);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    '#761 QA trail: room-close flip then Profile pushed twice quickly',
    (tester) async {
      menuOffAtOnce = true;
      await pumpHomeWithRoutes(tester);
      await setRooms(tester, const [ValueKey('beacon-room')]);
      await tester.pumpAndSettle();

      await setRooms(tester, const []);
      navigatorKey.currentState!.pushNamed('/profile');
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Profile overlay')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expectNoCrash(tester);

      while (navigatorKey.currentState!.canPop()) {
        navigatorKey.currentState!.pop();
      }
      await tester.pumpAndSettle();
      expectNoCrash(tester);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    '#761 phone width: menu flips do not build SelectionArea (Lobby Back path)',
    (tester) async {
      await usePhoneSurface(tester);
      BrowserContextMenuHold.isWeb = () => true;
      menuOffAtOnce = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light().copyWith(
            platform: TargetPlatform.iOS,
          ),
          locale: const Locale('ru'),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setOuter = setState;
                return Column(
                  children: [
                    const TenturaSelectionArea(child: Text(_outside)),
                    for (final key in rooms)
                      BrowserContextMenuHold(
                        key: key,
                        child: const TenturaSelectionArea(child: Text(_room)),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      expect(find.byType(SelectionArea), findsNothing);

      await setRooms(tester, const [ValueKey('lobby')]);
      await tester.pumpAndSettle();
      await setRooms(tester, const []);
      await tester.pumpAndSettle();
      expect(find.byType(SelectionArea), findsNothing);
      expectNoCrash(tester);
    },
  );
}
