// Desktop / web: the message actions open on right-click (also when the
// pointer is on the selectable message text), and from the keyboard with
// Enter, the Menu key or Shift+F10 on a message Tab has focused; the hover
// strip buttons (their tap targets) are at least 40 px (#456).
// Right-click while text is selected is deliberately not pinned here.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

const _viewer = Profile(id: 'me', displayName: 'Me');
const _body = 'Bring the ladder on Saturday';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => const Stream<ProfileState>.empty();
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      const Stream<Map<String, UserPresenceStatus>>.empty();
}

final _createdAt = DateTime.utc(2026, 10, 1, 12);

RoomMessage _ownMessage() => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: _viewer.id,
  author: _viewer,
  body: _body,
  createdAt: _createdAt,
);

/// Desktop platforms: [TenturaTheme.light] is built inside the test body, so
/// it picks up the overridden platform (desktop density, shrink-wrapped tap
/// targets and the desktop SelectionArea around message text), as on web.
final _desktop = TargetPlatformVariant.desktop();

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    required void Function(RoomMessage message) onActionsPressed,
    bool withTextField = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final tile = RoomMessageTile(
      message: _ownMessage(),
      myProfile: _viewer,
      onActionsPressed: onActionsPressed,
      onReplyPressed: (_) {},
      onToggleReaction: (_, _) async {},
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: withTextField
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 300,
                          child: TextField(
                            key: Key('Issue456.OtherField'),
                          ),
                        ),
                        Flexible(child: tile),
                      ],
                    )
                  : tile,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder bubble() =>
      find.byKey(TestIds.key(TestIds.roomMessageBubblePressScale));

  Finder bodyText() => find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText().contains(_body),
  );

  Future<void> rightClickAt(WidgetTester tester, Offset position) async {
    await tester.tapAt(
      position,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  /// Whether keyboard focus sits on the message itself: a real focus node
  /// (not a [FocusScopeNode] such as the route's scope) whose widget lies
  /// inside the [RoomMessageTile] and either wraps the bubble or sits inside
  /// it (keys then bubble up to the message's handler).
  bool messageHasFocus(WidgetTester tester) {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node is FocusScopeNode) return false;
    final focused = node.context;
    if (focused is! Element) return false;
    final tileElement = find.byType(RoomMessageTile).evaluate().single;
    final bubbleElement = bubble().evaluate().single;
    if (identical(focused, bubbleElement)) return true;

    // The focused element must be the tile or below it.
    var insideTile = identical(focused, tileElement);
    if (!insideTile) {
      focused.visitAncestorElements((e) {
        if (identical(e, tileElement)) insideTile = true;
        return !insideTile;
      });
    }
    if (!insideTile) return false;

    // ...and wrap the bubble, or be inside it.
    var related = false;
    bubbleElement.visitAncestorElements((e) {
      if (identical(e, focused)) related = true;
      // Stop at the tile: nothing above it counts.
      return !related && !identical(e, tileElement);
    });
    if (related) return true;
    focused.visitAncestorElements((e) {
      if (identical(e, bubbleElement)) related = true;
      return !related && !identical(e, tileElement);
    });
    return related;
  }

  /// Tabs through the screen until the message has keyboard focus. The
  /// message must not hold focus before any key is pressed, so this proves
  /// Tab itself reaches it.
  Future<void> focusMessageWithTab(WidgetTester tester) async {
    expect(
      messageHasFocus(tester),
      isFalse,
      reason: 'the message must not be focused before Tab is pressed',
    );
    var tabs = 0;
    while (tabs < 12 && !messageHasFocus(tester)) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      tabs++;
    }
    expect(tabs, greaterThan(0));
    expect(
      messageHasFocus(tester),
      isTrue,
      reason: 'Tab must be able to reach the chat message itself',
    );
  }

  group('right-click', () {
    testWidgets(
      'right-click on the message text opens the message actions once',
      (tester) async {
        var actions = 0;
        await pumpTile(tester, onActionsPressed: (_) => actions++);
        expect(bodyText(), findsWidgets);

        await rightClickAt(tester, tester.getCenter(bodyText().first));

        expect(actions, 1);
      },
      variant: _desktop,
    );

    testWidgets(
      'right-click on the bubble padding opens the message actions once',
      (tester) async {
        var actions = 0;
        await pumpTile(tester, onActionsPressed: (_) => actions++);

        final left = tester.getTopLeft(bubble()).dx;
        final middle = tester.getCenter(bubble()).dy;
        await rightClickAt(tester, Offset(left + 3, middle));

        expect(actions, 1);
      },
      variant: _desktop,
    );
  });

  group('keyboard', () {
    testWidgets(
      'Enter on the focused message opens the message actions',
      (tester) async {
        var actions = 0;
        await pumpTile(tester, onActionsPressed: (_) => actions++);
        await focusMessageWithTab(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(actions, 1);
      },
      variant: _desktop,
    );

    testWidgets(
      'Menu key on the focused message opens the message actions',
      (tester) async {
        var actions = 0;
        await pumpTile(tester, onActionsPressed: (_) => actions++);
        await focusMessageWithTab(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
        await tester.pumpAndSettle();

        expect(actions, 1);
      },
      variant: _desktop,
    );

    testWidgets(
      'Shift+F10 on the focused message opens the message actions',
      (tester) async {
        var actions = 0;
        await pumpTile(tester, onActionsPressed: (_) => actions++);
        await focusMessageWithTab(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.f10);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();

        expect(actions, 1);
      },
      variant: _desktop,
    );

    testWidgets(
      'Enter and Menu typed in another field do not open the message actions',
      (tester) async {
        var actions = 0;
        await pumpTile(
          tester,
          onActionsPressed: (_) => actions++,
          withTextField: true,
        );
        await tester.tap(find.byKey(const Key('Issue456.OtherField')));
        await tester.pumpAndSettle();
        expect(messageHasFocus(tester), isFalse);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
        await tester.pumpAndSettle();

        expect(actions, 0);
      },
      variant: _desktop,
    );
  });

  testWidgets(
    'hover strip icons are at least 40 px',
    (tester) async {
      final l10n = lookupL10n(const Locale('en'));
      await pumpTile(tester, onActionsPressed: (_) {});

      final center = tester.getCenter(bubble());
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: center);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(center);
      await tester.pumpAndSettle();

      for (final tooltip in [
        l10n.beaconRoomActionReply,
        l10n.beaconRoomReactionAddTooltip,
        l10n.beaconRoomMessageActionsTitle,
      ]) {
        // The tap target is the IconButton, not the Tooltip's child.
        final button = find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        );
        expect(button, findsOneWidget, reason: tooltip);
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(40), reason: tooltip);
        expect(size.height, greaterThanOrEqualTo(40), reason: tooltip);
      }
    },
    variant: _desktop,
  );
}
