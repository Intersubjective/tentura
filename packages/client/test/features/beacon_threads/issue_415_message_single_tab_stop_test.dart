// #415: on desktop/web Tab stopped twice on every chat message ("message
// x2" in the issue): once on the bubble itself (its own focus node, #456)
// and once more on the selectable text inside it (SelectionArea's focus
// node). Spec: a message is ONE Tab stop, the bubble; the next Tab leaves
// the message for the next control. And the text stays selectable: a click
// into it still puts focus in its SelectionArea (so Ctrl+A / Ctrl+C work).
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

import '../../support/a11y_focus.dart';

const _viewer = Profile(id: 'me', displayName: 'Me');
const _body = 'Bring the ladder on Saturday';
const _before = 'Control before';
const _after = 'Control after';

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

RoomMessage _ownMessage() => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: _viewer.id,
  author: _viewer,
  body: _body,
  createdAt: DateTime.utc(2026, 10, 1, 12),
);

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        // Built inside the test body: desktop platform, so the message text
        // sits in the desktop SelectionArea, as on web.
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(onPressed: () {}, child: const Text(_before)),
              Flexible(
                child: RoomMessageTile(
                  message: _ownMessage(),
                  myProfile: _viewer,
                  onActionsPressed: (_) {},
                  onReplyPressed: (_) {},
                  onToggleReaction: (_, _) async {},
                ),
              ),
              ElevatedButton(onPressed: () {}, child: const Text(_after)),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FocusNode _buttonNode(WidgetTester tester, String label) =>
    Focus.of(tester.element(find.text(label)));

/// Whether the primary focus is a node whose widget lies inside the tile.
bool _focusInsideTile() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  final tile = find.byType(RoomMessageTile).evaluate().single;
  var inside = false;
  focused.visitAncestorElements((e) {
    if (identical(e, tile)) inside = true;
    return !inside;
  });
  return inside;
}

/// Whether the primary focus wraps the bubble (the bubble's own node).
bool _focusWrapsBubble() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  return find
      .descendant(
        of: find.byElementPredicate((e) => e == focused),
        matching: find.byKey(TestIds.key(TestIds.roomMessageBubblePressScale)),
      )
      .evaluate()
      .isNotEmpty;
}

String _describeFocus() {
  final focus = FocusManager.instance.primaryFocus;
  return '${focus?.debugLabel ?? focus?.runtimeType} '
      '(${focus?.context?.widget.runtimeType})';
}

void main() {
  testWidgets(
    '#415 desktop: a chat message is one Tab stop, not two',
    (tester) async {
      await _pump(tester);
      // Precondition: the text is selectable here (the source of the extra
      // stop), and a fix must keep it so.
      expect(
        find.ancestor(
          of: find
              .byWidgetPredicate(
                (w) => w is RichText && w.text.toPlainText().contains(_body),
              )
              .first,
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
        reason: 'desktop message text stays selectable',
      );

      _buttonNode(tester, _before).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        _focusInsideTile() && _focusWrapsBubble(),
        isTrue,
        reason:
            'first Tab: the message bubble itself (#456); '
            'focus is on ${_describeFocus()}',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        _focusInsideTile(),
        isFalse,
        reason:
            'second Tab leaves the message (no second stop on its '
            'text); focus is on ${_describeFocus()}',
      );
      expect(
        FocusManager.instance.primaryFocus,
        same(_buttonNode(tester, _after)),
        reason: 'second Tab: the next control',
      );
    },
    variant: TargetPlatformVariant.desktop(),
  );
  testWidgets(
    '#415 desktop: clicking the message text still focuses its selection',
    (tester) async {
      await _pump(tester);
      final text = find
          .byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains(_body),
          )
          .first;
      await tester.tap(text, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      final area = tester.element(
        find.ancestor(of: text, matching: find.byType(SelectionArea)).first,
      );
      final focused = FocusManager.instance.primaryFocus?.context;
      var inside = false;
      focused?.visitAncestorElements((e) {
        if (identical(e, area)) inside = true;
        return !inside;
      });
      expect(
        inside,
        isTrue,
        reason:
            'a click into the message text focuses its SelectionArea '
            '(text stays keyboard-copyable); focus is on ${_describeFocus()}',
      );
    },
    variant: TargetPlatformVariant.desktop(),
  );
  testWidgets(
    '#415 desktop: Tab onto a message moves the browser focus to it',
    (tester) async {
      // On the web the browser focuses the element of the semantics node
      // that says it has focus. The bubble's focus node had no semantics, so
      // a Tab onto a message left the browser on the control before it
      // («More actions x2», «message group x2» in the QA run).
      final handle = tester.ensureSemantics();
      await _pump(tester);
      _buttonNode(tester, _before).requestFocus();
      // requestFocus applies in a microtask after this pump's (absent)
      // frame; the second pump rebuilds Focus's semantics with the focus.
      await tester.pump();
      await tester.pump();
      final before = focusedSemanticsNodes().map((n) => n.id).toSet();
      expect(before, isNotEmpty, reason: 'precondition: «before» is focused');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        _focusInsideTile() && _focusWrapsBubble(),
        isTrue,
        reason: 'precondition: Tab is on the bubble; on ${_describeFocus()}',
      );
      final nodes = focusedSemanticsNodes();
      expect(
        nodes,
        isNotEmpty,
        reason: 'a semantics node says the message has focus',
      );
      expect(
        nodes.map((n) => n.id).toSet(),
        isNot(equals(before)),
        reason: 'the browser focus leaves «before» for the message',
      );
      final bubble = tester.getRect(
        find.byKey(TestIds.key(TestIds.roomMessageBubblePressScale)),
      );
      final node = nodes.single;
      final size = node.rect.size;
      expect(
        size.width <= bubble.width + 2 && size.height <= bubble.height + 2,
        isTrue,
        reason:
            'the focused node is the message bubble (${bubble.size}), not a '
            'wider area: ${describeSemanticsNode(node)} sized $size',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        focusedSemanticsNodes().map((n) => n.id).toSet(),
        isNot(equals(nodes.map((n) => n.id).toSet())),
        reason: 'the next Tab moves the browser focus off the message',
      );
      handle.dispose();
    },
    variant: TargetPlatformVariant.desktop(),
  );
}
