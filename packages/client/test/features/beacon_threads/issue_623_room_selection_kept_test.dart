// #623 / owner review on #626: in the request room on web, a bubble hover
// used to turn the browser's own context menu off and on (#456); the next
// rebuild of the chat list (the author accepting an offer or changing the
// status inserts a system line) then crashed message text into a grey error
// box. Now the room holds the browser menu off once while it is mounted
// (BrowserContextMenuHold, from ThreadDetail) and the bubbles never flip it.
//
// Spec: select text in a message, hover out of that bubble and over another
// one, then a new line lands and the list rebuilds: no exception, no
// ErrorWidget, the selection is still there in the same selection region,
// and hovering never touched the browser menu. And ThreadDetail holds the
// menu for exactly as long as the room is mounted.
//
// kIsWeb is false in VM tests, so the web check and the browser-menu calls
// go through BrowserContextMenuHold's test seams.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/browser_context_menu_hold.dart';

const _viewer = Profile(id: 'me', displayName: 'Me');
const _helper = Profile(id: 'helper', displayName: 'Helper');

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

RoomMessage _message(String id, Profile author, String body, int minute) =>
    RoomMessage(
      id: id,
      beaconId: 'b1',
      authorId: author.id,
      author: author,
      body: body,
      createdAt: DateTime.utc(2026, 10, 21, 12, minute),
    );

const _first = 'Bring the ladder on Saturday';
const _second = 'I can bring mine too';
const _inserted = 'Status changed to Final check';

Finder _richText(String text) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText().contains(text),
);

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(_richText(text).first);

/// Global position of the caret before [offset] in a one-line [paragraph].
Offset _textPosition(RenderParagraph paragraph, int offset) {
  final caret = paragraph.getOffsetForCaret(
    TextPosition(offset: offset),
    Rect.zero,
  );
  return paragraph.localToGlobal(
    caret + Offset(0, paragraph.size.height / 2),
  );
}

void main() {
  final originalIsWeb = BrowserContextMenuHold.isWeb;
  final originalDisable = BrowserContextMenuHold.disableMenu;
  final originalEnable = BrowserContextMenuHold.enableMenu;
  late List<String> menuCalls;

  setUp(() {
    menuCalls = [];
    BrowserContextMenuHold.isWeb = () => true;
    BrowserContextMenuHold.disableMenu = () async {
      menuCalls.add('disable');
    };
    BrowserContextMenuHold.enableMenu = () async {
      menuCalls.add('enable');
    };
  });

  tearDown(() {
    BrowserContextMenuHold.isWeb = originalIsWeb;
    BrowserContextMenuHold.disableMenu = originalDisable;
    BrowserContextMenuHold.enableMenu = originalEnable;
  });

  testWidgets(
    '#623 a selection survives hovering other bubbles and a new line',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final messages = [
        _message('m1', _viewer, _first, 0),
        _message('m2', _helper, _second, 1),
      ];
      late StateSetter rebuildList;

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
              body: BrowserContextMenuHold(
                child: StatefulBuilder(
                  builder: (context, setState) {
                    rebuildList = setState;
                    return ListView(
                      children: [
                        for (final m in messages)
                          RoomMessageTile(
                            key: ValueKey(m.id),
                            message: m,
                            myProfile: _viewer,
                            onActionsPressed: (_) {},
                            onReplyPressed: (_) {},
                            onToggleReaction: (_, _) async {},
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(menuCalls, ['disable'], reason: 'the room turns the menu off');
      expect(
        find.ancestor(
          of: _richText(_first).first,
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
        reason: 'precondition: desktop message text is selectable',
      );

      // Drag-select "Bring the" in the first message with the mouse.
      final first = _paragraph(tester, _first);
      final mouse = await tester.startGesture(
        _textPosition(first, 0),
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await tester.pump();
      await mouse.moveTo(_textPosition(first, 9));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(first.selections, isNotEmpty);
      expect(first.selections.first.isCollapsed, isFalse);
      final region = tester.state<SelectableRegionState>(
        find
            .ancestor(
              of: _richText(_first).first,
              matching: find.byType(SelectableRegion),
            )
            .first,
      );

      // Hover out of the bubble, over the other message, and off the list.
      await mouse.moveTo(tester.getCenter(_richText(_second).first));
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(890, 690));
      await tester.pumpAndSettle();
      expect(
        menuCalls,
        ['disable'],
        reason: 'hovering bubbles must not flip the browser menu',
      );

      // The author's status change lands as a new line; the list rebuilds.
      rebuildList(
        () => messages.add(_message('m3', _helper, _inserted, 2)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(_richText(_inserted), findsWidgets);
      final firstAfter = _paragraph(tester, _first);
      expect(
        firstAfter.selections,
        isNotEmpty,
        reason: 'the selection is kept across the rebuild',
      );
      expect(firstAfter.selections.first.isCollapsed, isFalse);
      expect(
        tester.state<SelectableRegionState>(
          find
              .ancestor(
                of: _richText(_first).first,
                matching: find.byType(SelectableRegion),
              )
              .first,
        ),
        same(region),
        reason: 'the message keeps its selection region (no remount)',
      );
      expect(menuCalls, ['disable']);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    '#623 the room holds the browser menu off for as long as it is mounted',
    (tester) async {
      // Closed in the test body, not in a tear-down: its futures belong to
      // this test's fake clock, and awaiting them after the test hangs.
      final host = ThreadHostCubit(beaconId: 'b1');
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: BlocProvider<ThreadHostCubit>.value(
              value: host,
              child: ThreadDetail(
                thread: RequestThread(
                  threadId: RequestThread.generalId,
                  kind: RequestThreadKind.general,
                  lastSeenAt: DateTime.utc(2026, 10, 21),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(BrowserContextMenuHold), findsOneWidget);
      expect(menuCalls, ['disable']);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(menuCalls, ['disable', 'enable']);
      expect(BrowserContextMenuHold.activeHolds, 0);
      await host.close();
    },
  );
}
